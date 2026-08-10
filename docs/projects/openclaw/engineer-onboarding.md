# Engineer Onboarding

For a new engineer joining the ReadyMode Bot project on day 1. Goal: understand the system well enough to add an operation or debug a production issue without breaking anything.

Read [`overview.md`](./overview.md), [`architecture.md`](./architecture.md), and [`incidents.md`](./incidents.md) first. This doc is the hands-on complement.

---

## 1. Mental Model in 60 Seconds

```
Discord message
  → Bot (nextcord listener)
  → Validation
  → Intent Parser (Claude Haiku) → structured { intent, params }
  → Dispatcher (job lock) → executor or kb.py
  → Executor (Playwright headless Chromium) → { success, data }
  → Responder (Claude Haiku) → natural-language Discord reply
```

Six layers. Each does one thing and passes a typed result to the next.

| Layer | Does | Does NOT do |
|---|---|---|
| Intent Parser | Extract structured intent from natural language | Touch the browser, know ReadyMode UI |
| Dispatcher | Route intent to the right executor | Parse language, talk to Discord |
| Executor | Drive Playwright through ReadyMode UI | Format user-facing text, know Discord |
| Responder | Phrase results as a human-readable Discord reply | Know selectors, know ReadyMode |

If you find a CSS selector in a prompt file, or a Discord message string in an executor, that is a layer violation — move it.

---

## 2. Critical Patterns (Read Before Touching Any Executor)

### Pattern A — React input: native value setter

ReadyMode is a React SPA. Setting `element.value = x` directly bypasses React's state system. The field looks filled, the form submits empty. Always use:

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

This pattern applies to every input in ReadyMode. The `set_pass` field additionally uses a dynamic `xname` attribute that only becomes `name` after `oninput` fires — skipping `dispatchEvent` means the field is never submitted. See [Incident 10](./incidents.md).

### Pattern B — Navigation via dash_link clicks

ReadyMode is a React SPA. Direct URL navigation skips the React bootstrap and returns a blank DOM — no elements, no error, just nothing. Always click `a.dash_link` elements.

```python
link = await page.query_selector(f"a.dash_link >> text={section_name}")
await link.click()
await page.wait_for_load_state("networkidle")
```

**Known exception:** `/+Team/ManageLicenses` supports direct navigation. Document any new exceptions you find, and verify them on a cold browser before adding.

### Pattern C — Queue discovery with retry loop

ReadyMode renders queue lists asynchronously. Reading queue elements immediately after navigation returns an empty list. This caused a production bug (see [Incident 16](./incidents.md)).

```python
queues = []
for _ in range(6):
    queues = await page.query_selector_all(".queue-item")
    if queues:
        break
    await asyncio.sleep(0.5)
```

Always sweep ALL queues — do not stop at the first queue with content. Do not write the result catalog until all queues are swept; a partial sweep must be discarded. See [Incident 17](./incidents.md).

### Pattern D — Post-login overlay dismissal

ReadyMode sometimes renders a modal overlay (`#phone_test_ui`, z-index 600) immediately after login, intercepting all clicks. Always dismiss it before navigating.

### Pattern E — Login result validation

After completing the login flow, explicitly verify that login succeeded — check for a known post-login DOM indicator (e.g. presence of `a.dash_link` elements). A wrong redirect or silent credential rejection looks identical to success from the outside. See [Incident 12](./incidents.md).

---

## 3. Adding a New Operation — End to End

### Step 1 — Inspect the DOM first

Before writing any code:

1. Open the target ReadyMode instance in a real browser and perform the operation manually while watching DevTools.
2. Note the exact `a.dash_link` text used for navigation.
3. Identify selectors for every input, button, and confirmation dialog.
4. Check if the operation can be done via a direct `fetch/POST` to an internal endpoint (direct calls are more reliable than UI clicks when available).

Do not write selectors from memory or screenshots. ReadyMode's DOM differs per tenant.

### Step 2 — Create the executor

Create `executors/<operation_name>.py`. Follow this contract:

```python
async def run(page, params: dict) -> dict:
    """
    Returns:
        { "success": True,  "data": { ... } }
        { "success": False, "error": "human-readable message" }
    """
    try:
        # login
        # dismiss overlay
        # navigate via dash_link
        # fill inputs with native value setter
        # verify final state before returning success
        # logout
        return {"success": True, "data": {...}}
    except Exception as e:
        return {"success": False, "error": str(e)}
```

Rules:

- Always logout, even on failure paths where a session was opened.
- Never return `success: true` without verifying the final state (e.g. check member count after assignment, not just that the button was clicked).
- Executors are synchronous from the dispatcher's perspective — the job lock is held for the full duration.

### Step 3 — Register the intent

Add the new intent to `intent_parser_system_prompt.txt` and a matching route in `dispatcher.py`.

### Step 4 — Update the responder prompt

Add example output phrases for the new operation in both ES and EN to `responder_system_prompt.txt`.

### Step 5 — Test with cli.py before Discord

```bash
python tools/cli.py --intent create_playlist --params '{"name": "TestPlaylist", "campaigns": ["US East"]}'
```

This runs the full dispatcher → executor → responder pipeline without Discord. You pass intent and params directly, bypassing the intent parser.

### Step 6 — Test on a non-production account

See section 4. Never test against a live client account.

---

## 4. Local Dev and Testing

### Using cli.py

`tools/cli.py` runs the pipeline without Discord. Use it for all initial executor development.

### Testing against a non-production account

Set `READYMODE_URL`, `READYMODE_USERNAME`, and `READYMODE_PASSWORD` in your `.env` to point at a dedicated test ReadyMode account. Never test against a live client instance — a misfire creates real accounts, resets real leads, or clears real licenses.

### READYMODE_HEADLESS

Keep it `true` even locally. If you set it to `false` to watch the browser, re-test headless before committing — some timing issues only appear in headless mode.

### Container isolation

Spin up a test Docker Compose instance with a test `.env` in a separate directory. Do not share the Docker network with production containers.

---

## 5. Deploying a New Agency

```bash
# 1. Create the agency branch
git checkout main && git pull
git checkout -b agency/<name>

# 2. Create .env for the agency
cat > .env << EOF
READYMODE_URL=https://<name>.readymode.com
READYMODE_USERNAME=...
READYMODE_PASSWORD=...
DISCORD_TOKEN=...
ANTHROPIC_API_KEY=...
ALLOWED_CHANNEL_IDS=...
READYMODE_HEADLESS=true
EOF

git add .env && git commit -m "init agency/<name>"
git push -u origin agency/<name>

# 3. Set up on EC2
mkdir -p /opt/readymode-bots/<name>
cd /opt/readymode-bots/<name>
git clone --branch agency/<name> <repo-url> .

# 4. Register systemd unit
cp deploy/readymode-bot.service /etc/systemd/system/readymode-<name>.service
# Edit WorkingDirectory and Description in the unit file
systemctl daemon-reload
systemctl enable readymode-<name>
systemctl start readymode-<name>

# 5. Verify
docker ps --filter "name=deploy-bot-<name>"
journalctl -u readymode-<name> -f
```

**Ticket channel access:** If the agency uses Discord tickets, add the bot application as a Support role within each brand's ticket panel settings — not as a server-wide role. Adding the role server-wide causes 403 errors when the bot tries to read ticket channels. See [Incident 13](./incidents.md).

---

## 6. Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| `input.value = x` instead of native setter | Field appears filled, form submits empty | Pattern A: native value setter |
| Direct URL navigation | Blank DOM, selector not found | Pattern B: click `a.dash_link` |
| Reading queue list without retry | Empty list even though queues exist in ReadyMode | Pattern C: 6-retry loop |
| Stopping at the first populated queue | Misses other queues, incomplete catalog | Always traverse ALL queues |
| Not verifying login result | Silent failure, all subsequent clicks 404 | Pattern E: check post-login DOM indicator |
| Renaming a running container | `sandbox not found` error | Stop → rename → restart |
| `READYMODE_HEADLESS=false` on EC2 | Browser crashes silently | EC2 has no display; keep headless |
| Adding bot as server-wide role for tickets | 403 on ticket channel read | Add bot to ticket panel as Support role specifically |

---

## 7. What to Read Next

1. [`overview.md`](./overview.md) — System purpose and fleet status.
2. [`architecture.md`](./architecture.md) — Full 6-layer detail, branch strategy, Docker deployment.
3. [`incidents.md`](./incidents.md) — Read all incidents before touching any executor.
4. [`operations.md`](./operations.md) — Per-operation detail.
5. [`fleet-status.md`](./fleet-status.md) — Current account inventory and known issues.
6. [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) — What's still open and why.
7. [`security-audit.md`](./security-audit.md) — Server posture and what not to touch.
