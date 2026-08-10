# Architecture

**Version:** 2.0 — Python + Playwright + Claude Haiku  
**Replaced:** OpenClaw Node.js gateway + bash scripts + CDP (June 2026)

---

## 6-Layer Pipeline

Every Discord message passes through six layers in strict order. Each layer has a single responsibility and passes a typed result to the next.

```
Discord message
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 1 — Bot  (bot.py)                                │
│  nextcord listener. Filters by ALLOWED_CHANNEL_IDS      │
│  or ALLOWED_CHANNEL_REGEX. Passes raw message object.   │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 2 — Validation  (validation.py)                  │
│  Checks message format and required presence.           │
│  Rejects early with a user-facing error if invalid.     │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 3 — Intent Parser  (intent_parser.py)            │
│  Single Claude Haiku call.                              │
│  Returns: { intent, params, confidence }                │
│  System prompt: prompts/intent_parser_system_prompt.txt │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 4 — Dispatcher  (dispatcher.py)                  │
│  Routes intent → executor or kb.py.                     │
│  Acquires global job lock before calling any executor.  │
│  kb_support skips layers 4-5 entirely.                  │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 5 — Executor  (executors/*.py)                   │
│  Playwright headless Chromium session.                  │
│  One Python file per operation.                         │
│  Returns: { success, data, error? }                     │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│  Layer 6 — Responder  (responder.py)                    │
│  Single Claude Haiku call.                              │
│  Converts executor result → natural-language reply.     │
│  System prompt: prompts/responder_system_prompt.txt     │
│  Detects message language (ES/EN) and responds in kind. │
└─────────────────────────────────────────────────────────┘
      │
      ▼
Discord reply
```

---

## File Structure

```
readymode-bot/
├── bot.py                          # Layer 1 — nextcord Discord listener
├── validation.py                   # Layer 2 — input validation
├── intent_parser.py                # Layer 3 — Claude Haiku intent extraction
├── dispatcher.py                   # Layer 4 — intent routing + job lock
├── responder.py                    # Layer 6 — Claude Haiku response phrasing
├── kb.py                           # KB support — bilingual Q&A dict, no Playwright
├── requirements.txt
├── DECISIONS.md                    # Architecture decision log
├── .env                            # Per-agency secrets (never committed)
│
├── executors/
│   ├── create_user.py              # Create user account + playlist + assignment
│   ├── create_playlist.py          # Create standalone playlist
│   ├── reset_leads.py              # Reset leads queue for a named agent
│   ├── clear_licenses.py           # Sign out inactive users
│   ├── user_exists.py              # Check if agent account exists
│   ├── user_playlist.py            # Find which playlist an agent belongs to
│   └── playlist_members.py         # List all members of a playlist
│
├── prompts/
│   ├── intent_parser_system_prompt.txt
│   └── responder_system_prompt.txt
│
├── deploy/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── readymode-bot.service       # systemd unit template
│
├── tools/
│   └── cli.py                      # Local CLI for testing without Discord
│
└── tests/
    └── test_anthropic_token.py     # Validate Anthropic API credentials
```

---

## Per-Agency Branch Strategy

Each agency lives on its own git branch: `agency/<agency-name>`. The `main` branch contains no agency-specific configuration.

```
main                            # baseline — clean, no credentials
  ├── agency/jamesgaviria
  ├── agency/zenithfinancial
  ├── agency/ascenti
  └── ...
```

**What changes per branch:** `.env` (credentials, URLs, Discord token, API key, channel IDs). Optionally `ALLOWED_CHANNEL_REGEX` if the agency uses ticket-channel routing.

**What never changes per branch:** All Python files, executor logic, prompts. If you find yourself editing `executors/create_user.py` on an agency branch, stop — that fix goes into `main` and is merged into every branch.

### Creating a branch for a new agency

```bash
git checkout main && git pull
git checkout -b agency/<name>
# Create .env with the agency's credentials
git add .env
git commit -m "init agency/<name>"
git push -u origin agency/<name>
```

### Propagating a main fix to all agency branches

```bash
git checkout main
# Make and commit the fix
git push

# For each active agency:
git checkout agency/<name>
git merge main
git push
```

---

## .env Configuration Reference

| Variable | Required | Description |
|---|---|---|
| `READYMODE_URL` | ✅ | Full URL of the agency's ReadyMode instance |
| `READYMODE_USERNAME` | ✅ | ReadyMode admin/manager login |
| `READYMODE_PASSWORD` | ✅ | ReadyMode admin/manager password |
| `DISCORD_TOKEN` | ✅ | Bot token for this agency's dedicated Discord application |
| `ANTHROPIC_API_KEY` | ✅ | Anthropic key — one per agency (all rotated 2026-08-05) |
| `ALLOWED_CHANNEL_IDS` | ✅ | Comma-separated Discord channel IDs the bot listens in |
| `ALLOWED_CHANNEL_REGEX` | Optional | Regex matched against channel names for ticket-system routing (added 2026-08-03, commit d3bd75d) |
| `READYMODE_HEADLESS` | Optional | Default `true`. **Never set to `false` in production.** |

`ALLOWED_CHANNEL_IDS` and `ALLOWED_CHANNEL_REGEX` are evaluated as OR — matching either is sufficient.

---

## Docker Deployment

Each agency runs as an isolated Docker container, started and monitored by a systemd unit.

### Directory layout on EC2

```
/opt/readymode-bots/
├── jamesgaviria/
│   ├── .env
│   └── docker-compose.yml
├── zenithfinancial/
│   ├── .env
│   └── docker-compose.yml
└── <agencyname>/
    ├── .env
    └── docker-compose.yml
```

Container names follow the pattern `deploy-bot-<agencyname>`.

### systemd unit (template)

```ini
[Unit]
Description=ReadyMode Bot — <agencyname>
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/opt/readymode-bots/<agencyname>
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Common commands

```bash
# Check all bot containers
docker ps --filter "name=deploy-bot"

# Restart one agency
systemctl restart readymode-<agencyname>

# Follow logs for one agency
journalctl -u readymode-<agencyname> -f

# Deploy an updated branch
cd /opt/readymode-bots/<agencyname>
git pull origin agency/<agencyname>
systemctl restart readymode-<agencyname>
```

**Important:** Do not rename a running container. Stop the container first, rename, then restart. Renaming a live container causes a `sandbox not found` error. See [Incident 15](./incidents.md).

---

## EC2 Sizing

| Fleet size | Instance type | RAM |
|---|---|---|
| ≤ 4 agencies | t3.medium | 4 GB |
| 5–8 agencies | t3.large | 8 GB |
| 9–15 agencies | t3.xlarge | 16 GB |
| 15+ agencies | t3.xlarge or two servers | 16 GB+ |

At 15 accounts, the fleet sits at the t3.xlarge / two-server boundary. Each Playwright + Chromium instance uses approximately 300–500 MB RSS under load.

**The bot requires zero inbound ports.** All connections are outbound: Discord WebSocket, Anthropic HTTPS, ReadyMode HTTPS. No load balancer, no SSL certificate, no Cloudflare tunnel needed for the bot tier.

---

## Critical Playwright Patterns

All executors must follow these patterns. Deviating causes intermittent, hard-to-reproduce failures.

### 1 — React input: native value setter

ReadyMode is a React SPA. `input.value = x` bypasses React's state system; the field submits empty. Always use:

```python
await page.evaluate(
    """([el, val]) => {
        const setter = Object.getOwnPropertyDescriptor(
            HTMLInputElement.prototype, 'value'
        ).set;
        setter.call(el, val);
        el.dispatchEvent(new Event('input', { bubbles: true }));
    }""",
    [element, value]
)
```

Note: the `set_pass` field uses a dynamic `xname` attribute that only becomes `name` after `oninput` fires. Skipping the `dispatchEvent` means the field is never submitted. See [Incident 10](./incidents.md).

### 2 — Navigation: click dash_link, not direct URL

ReadyMode is a React SPA. Direct URL navigation skips the React bootstrap and returns a blank DOM. Always navigate by clicking `a.dash_link` elements.

```python
link = await page.query_selector(f"a.dash_link >> text={section_name}")
await link.click()
await page.wait_for_load_state("networkidle")
```

Known exception: `/+Team/ManageLicenses` supports direct navigation. Document any new exceptions you discover and verify them on a cold browser.

### 3 — Queue discovery: 6-retry loop

ReadyMode renders queue lists asynchronously. Reading elements immediately after navigation returns an empty list.

```python
queues = []
for _ in range(6):
    queues = await page.query_selector_all(".queue-item")
    if queues:
        break
    await asyncio.sleep(0.5)
```

Always sweep ALL queues. Do not stop at the first queue with content. Do not write the catalog until all queues are swept — a partial sweep must be discarded. See [Incidents 16 and 17](./incidents.md).

### 4 — Post-login overlay dismissal

ReadyMode sometimes renders a modal overlay (`#phone_test_ui`, z-index 600) immediately after login, intercepting all subsequent clicks. Dismiss it before navigating.

### 5 — Login result validation

After the login flow completes, explicitly check for a known post-login DOM indicator (e.g. presence of `a.dash_link` elements) before proceeding. A wrong redirect or silent rejection looks identical to success from the outside. See [Incident 12](./incidents.md).
