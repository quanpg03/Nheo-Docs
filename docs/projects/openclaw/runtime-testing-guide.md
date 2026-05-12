# OpenClaw ReadyMode Bot — Runtime Testing Guide

> Comprehensive runtime testing manual for the ReadyMode Support Discord bot. Covers Discord-side and server-side test paths, the full T1–T18 battery, troubleshooting, and known non-bugs.

---

## 1. Overview

**ReadyMode Support** is an LLM-driven Discord bot that automates operator-level tasks inside the ReadyMode CRM web app via a Chrome headless instance controlled over CDP.

| Field                | Value                                                                 |
| -------------------- | --------------------------------------------------------------------- |
| Discord display name | `ReadyMode Support`                                                   |
| Discord user ID      | `1491866571818139718`                                                 |
| Guild ID             | `1476748033134956756`                                                 |
| Channel ID           | `1491870539713609848`                                                 |
| ReadyMode account    | `readymode` (server-side process user `agent`)                        |
| Pivot domain         | `breaddialer.readymode.com` (Arpa Growth suspended since April 2026)  |
| Admin login flag     | `READYMODE_LOGIN_AS_ADMIN=1` → logs in as shared `manager` account    |
| Chrome CDP port      | `18800`                                                               |
| Host                 | `159.89.179.179` (SSH on port `22022`)                                |

### What the bot does

The bot reads a Discord message, decides via its LLM + the `SKILL.md` decision table, and either:

1. Replies conversationally (smoke, KB queries, ambiguous requests),
2. Invokes a bash script in `/home/agent/.openclaw/workspace-readymode/skills/readymode-support/scripts/` that drives Chrome.

### Scripts available

| Script               | Purpose                                                  | Destructive? |
| -------------------- | -------------------------------------------------------- | ------------ |
| `create_user.sh`     | Create operator user; assign states + campaigns          | Yes (real)   |
| `clear_licenses.sh`  | Wipe license assignments for a user                      | Yes          |
| `upload_leads.sh`    | Upload a CSV of leads into a campaign                    | Yes          |
| `reset_leads.sh`     | NOT IMPLEMENTED — bot replies "no automatizado" + phone  | n/a          |

### Where things live on the server

```text
/home/agent/.openclaw/
├── workspace-readymode/
│   └── skills/readymode-support/
│       ├── SKILL.md                  # decision table (LLM prompt)
│       ├── scripts/*.sh              # automation scripts
│       └── screenshots/*.png         # 73-byte pointer files (see §5)
├── media/browser/<uuid>.png          # real PNG payloads
├── state/readymode-halt.flag         # circuit-breaker flag
└── logs/readymode/*.jsonl            # session logs
```

---

## 2. Testing in Discord

### 2.1 Joining the bot's channel

1. Accept the guild invite for guild `1476748033134956756` (ask Miguel for the invite link if you don't have access yet).
2. Open channel `#readymode-support` — channel ID `1491870539713609848`.
3. Confirm the bot's presence dot is green in the member sidebar.

### 2.2 Channel configuration

The bot is configured with `requireMention: false`, which means:

- You **do not** need to `@ReadyMode Support` to address it.
- Any message dropped in the channel is consumed.
- Do not write off-topic chatter there — it will be parsed as intent.

### 2.3 Phrases the bot understands

Pulled from the `SKILL.md` decision table. Both ES and EN forms are accepted, but the bot tends to reply in Spanish (see §6).

| Intent              | Spanish phrasing                                          | English phrasing                            |
| ------------------- | --------------------------------------------------------- | ------------------------------------------- |
| Smoke / capabilities| "hola", "qué puedes hacer", "ayuda"                       | "hi", "what can you do", "help"             |
| Create user         | "crea usuario `<name>` estados `<X,Y>` campañas `<C>`"    | "create user `<name>` states ... campaigns ..." |
| Clear licenses      | "limpia licencias de `<user>`", "clear licenses"          | "clear licenses for `<user>`"               |
| Upload leads        | "sube los leads a `<campaign>`" (+ CSV attached)          | "upload leads to `<campaign>`"              |
| Reset leads         | "reset leads de `<user>`"                                 | "reset leads for `<user>`"                  |
| KB query (support)  | "línea de soporte", "horario", "contacto"                 | "support line", "hours"                     |

### 2.4 Smoke test: is the bot alive?

Send in the channel:

```text
hola dime qué puedes hacer
```

Expected: a short Spanish reply listing create user / clear licenses / upload leads / reset leads / support contact. Typical latency: 2–6 s.

If no reply in 30 s, check the HALT flag (§5.1) and the gateway health (§3.3).

### 2.5 Monitoring bot logs from SSH

```bash
ssh -p 22022 -i ~/.ssh/id_rsa miguel@159.89.179.179

# Tail the current readymode session log
sudo -n -u agent bash -c 'ls -1t /home/agent/.openclaw/logs/readymode/*.jsonl | head -1 | xargs -I{} tail -F {}'

# Pretty-print one line
sudo -n -u agent bash -c 'tail -1 /home/agent/.openclaw/logs/readymode/*.jsonl' | jq .
```

JSONL fields of interest: `ts`, `kind` (`user_msg` | `tool_call` | `script_stdout` | `assistant_msg`), `script`, `exitCode`, `stderr`.

---

## 3. Testing on the server (CLI / TUI)

### 3.1 SSH in

```bash
ssh -p 22022 -i ~/.ssh/id_rsa miguel@159.89.179.179
```

> SSH port is **22022** (NHE-29 migrated it off 22). If you get a timeout, run `nc -zv 159.89.179.179 22022` before blaming firewall.

### 3.2 One-shot agent message (does NOT round-trip through Discord)

Useful for fast iteration without polluting the channel:

```bash
sudo -n -u agent bash -c "cd /home/agent && \
  /usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs \
  agent --agent readymode --message \"hola dime qué puedes hacer\""
```

Replace the quoted message for each test. The reply prints to stdout. The session is **ephemeral** — no multi-turn state is preserved across invocations.

### 3.3 Multi-turn TUI

For tests that require confirmation prompts (T5, T6) or chained turns:

```bash
sudo -n -u agent bash -c "/usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs \
  tui --session readymode-manual-$(date +%s)"
```

Each invocation gets a unique session key so logs are easy to find.

### 3.4 Gateway health

```bash
sudo -n -u agent bash -c "/usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs health"
```

Expected output: Discord gateway `connected`, plugin `readymode-support` `loaded`, Chrome CDP reachable on `localhost:18800`.

---

## 4. Test battery T1–T18

Legend:
- ✅ already validated today (2026-05-12)
- ⚠️ known imperfect behavior (see §6)
- ⏳ pending multi-turn / Discord round-trip
- 🔴 destructive on the real CRM — coordinate with Miguel before running

### T1 — Smoke ✅

| Field | Value |
| --- | --- |
| Message | `hola dime qué puedes hacer` |
| Expected | Short Spanish capability list (create user / clear licenses / upload leads / reset leads / support contact) |
| Verify | Reply within ~6 s; no script invocation in JSONL |

### T2 — Create user, single state ✅

| Field | Value |
| --- | --- |
| Message | `crea usuario testbot04 estados TX campañas Main` |
| Expected | "Usuario `testbot04` creado" + confirmation of states/campaigns |
| Verify | JSONL contains `tool_call` → `create_user.sh` with `exitCode:0`; Chrome screenshot in `/home/agent/.openclaw/media/browser/` |

### T3 — Create user, multi-state, auto-kick ✅

| Field | Value |
| --- | --- |
| Message | `crea usuario testbot05 estados CA,TX campañas Main` |
| Expected | User created. Bot will auto-kick any human session on `manager` (logged warning, then proceeds) |
| Verify | JSONL line `kick_event:true`; final `exitCode:0`. Warn Miguel before running if he's actively logged in. |

### T4 — Create user without params ✅

| Field | Value |
| --- | --- |
| Message | `crea usuario` |
| Expected | Clarification prompt asking for name + states + campaigns. **No script call.** |
| Verify | No `tool_call` entry in JSONL |

### T5 — Clear licenses → confirm yes ⏳ 🔴

Requires multi-turn (TUI or Discord). Two messages:

```text
> limpia licencias de testbot04
< ¿Confirmas limpiar todas las licencias de testbot04? (sí/no)
> si
< Limpiando…  → Listo.
```

Verify: `clear_licenses.sh` invoked with `exitCode:0`. Screenshot of licenses page post-clear.

### T6 — Clear licenses → confirm no ⏳

Same start, but reply `no`:

```text
> limpia licencias de testbot04
< ¿Confirmas limpiar todas las licencias de testbot04? (sí/no)
> no
< Ok, cancelo la operación.
```

Verify: **no** `tool_call` for `clear_licenses.sh`. Final assistant message is a polite cancel.

### T7 — Upload leads with CSV attachment ⏳ 🔴

Only testable via Discord (CSV upload). Use the prepared file at `/home/apolo/leads_test.csv`.

1. Attach the CSV to the next Discord message.
2. Send: `sube los leads a Main`
3. Expected: Bot acknowledges, runs `upload_leads.sh`, returns row count + campaign name.

Verify: JSONL `upload_leads.sh exitCode:0`; ReadyMode campaign view shows the new leads.

### T8 — Upload leads, no attachment ✅

| Field | Value |
| --- | --- |
| Message | `sube los leads a Main` |
| Expected | "Necesito un CSV adjunto" (or similar) — no script call |
| Verify | No `tool_call` in JSONL |

### T9 — KB query: hours ⚠️

| Field | Value |
| --- | --- |
| Message | `¿cuál es el horario de soporte?` |
| Expected (KB verbatim) | `Lun–Vie 6am–6pm PT` |
| Actual today | LLM paraphrases; sometimes adds extra context not in KB |
| Severity | Cosmetic — see §6 |

### T10 — KB query: contact email ⚠️

| Field | Value |
| --- | --- |
| Message | `email de soporte` |
| Expected (KB verbatim) | `support@readymode.com` |
| Actual today | LLM paraphrases ("puedes escribir a…") |

### T11 — KB query: ticket portal ⚠️

| Field | Value |
| --- | --- |
| Message | `portal de tickets` |
| Expected | KB URL verbatim |
| Actual today | LLM improvises |

### T12 — KB query: escalation ⚠️

| Field | Value |
| --- | --- |
| Message | `¿cómo escalo un problema?` |
| Expected | KB escalation steps verbatim |
| Actual today | LLM rewrites in its own words |

### T13 — Support line ✅

| Field | Value |
| --- | --- |
| Message | `línea de soporte` |
| Expected (verbatim) | `1 (800) 694-1049 ext. 4` |
| Verify | Exact string appears in reply |

### T14 — Reset leads (unimplemented path) ✅

| Field | Value |
| --- | --- |
| Message | `reset leads de Juan` |
| Expected | "Esa operación no está automatizada todavía. Llama al `1 (800) 694-1049 ext. 4`" |
| Verify | No `reset_leads.sh` invocation (script does not exist) |

### T15 — Invalid USPS state code ⚠️ 🔴

| Field | Value |
| --- | --- |
| Message | `crea usuario testbot06 estados ZZ campañas Main` |
| Expected | Bot should reject `ZZ` |
| Actual today | `create_user.sh` proceeds; user is created without that state license. **Not a regression** — script lacks state validation (NHE-44 G14). |

### T16 — English input ⚠️

| Field | Value |
| --- | --- |
| Message | `clear licenses for testbot04 please` |
| Expected | Bot understands and asks for confirmation in English |
| Actual today | Bot understands intent, replies in Spanish (cosmetic — §6) |

### T17 — Two intents in one message ⏳

| Field | Value |
| --- | --- |
| Message | `crea usuario testbot07 estados TX campañas Main y limpia licencias de testbot05` |
| Expected | Bot should sequence: ask for clarification or execute one then prompt for the other. |
| Verify | Inspect JSONL — should see at most one `tool_call` before a clarifying message |

### T18 — HALT flag active ⏳

Pre-condition: HALT flag present.

```bash
sudo -n -u agent touch /home/agent/.openclaw/state/readymode-halt.flag
```

Then send any actionable command (e.g., `crea usuario testbot99 estados TX campañas Main`).

Expected: Bot replies with a maintenance/halt message and does **not** invoke any script.

Cleanup:

```bash
sudo -n -u agent rm /home/agent/.openclaw/state/readymode-halt.flag
```

---

## 5. Troubleshooting

### 5.1 HALT flag

A file at `/home/agent/.openclaw/state/readymode-halt.flag` short-circuits all destructive script paths.

```bash
# Check
sudo -n -u agent test -f /home/agent/.openclaw/state/readymode-halt.flag && echo "HALTED" || echo "ok"

# Clear
sudo -n -u agent rm -f /home/agent/.openclaw/state/readymode-halt.flag
```

When the flag is set, the bot still replies conversationally but refuses to drive Chrome.

### 5.2 "already logged in"

Symptom: script aborts with an `already logged in` modal error from ReadyMode.

Cause: shared `manager` account collision — a human (likely Miguel) is logged in elsewhere.

Fix: patch **C2** auto-kicks the human session and retries the login. If the patch is active you'll see `kick_event:true` in the JSONL and the script proceeds. If you still see the error, the patch may have regressed — alert Miguel before forcing again.

Long-term: NHE-56 G22 (dedicated bot account) closes this class permanently.

### 5.3 "tomando tiempo inusualmente largo"

The bot LLM sometimes posts an "this is taking unusually long" message **before** the underlying script has actually finished. The script almost always completes successfully a few seconds later.

Verify by tailing the JSONL: if `exitCode:0` arrives after the impatience message, the operation succeeded. Don't re-run.

### 5.4 Screenshots are 73-byte pointers

Files in `/home/agent/.openclaw/workspace-readymode/skills/readymode-support/screenshots/*.png` are **73-byte pointer stubs**, not real PNGs. The actual image lives at `/home/agent/.openclaw/media/browser/<uuid>.png`.

```bash
# Find real PNG referenced by a pointer
sudo -n -u agent cat /home/agent/.openclaw/workspace-readymode/skills/readymode-support/screenshots/<name>.png
# → outputs e.g. "media/browser/<uuid>.png"

# Copy real one back to local
scp -P 22022 -i ~/.ssh/id_rsa \
  miguel@159.89.179.179:/home/agent/.openclaw/media/browser/<uuid>.png \
  /tmp/
```

### 5.5 Chrome CDP unreachable

If `health` reports CDP not reachable on `18800`:

```bash
# Status
sudo -n -u agent bash -c "curl -sS http://localhost:18800/json/version" | jq .

# Restart Chrome — only with explicit Miguel approval (production bot is live)
```

> Do not restart Chrome or any readymode service without an explicit go-ahead. The bot is live in production.

---

## 6. Known issues — NOT new bugs

Do not file these as regressions. They are tracked elsewhere or are accepted current behavior.

| # | Issue                                                                                       | Status / Tracker         |
| - | ------------------------------------------------------------------------------------------- | ------------------------ |
| 1 | LLM paraphrases KB answers when multiple matches exist (T9–T12)                             | Prompt-tuning backlog    |
| 2 | Bot replies in Spanish even when prompted in English (T16)                                  | Style decision, deferred |
| 3 | `create_user.sh` does not validate USPS state codes; accepts `ZZ` (T15)                     | NHE-44 G14a-e            |
| 4 | Playlist drag-and-drop for states/campaigns not implemented; assignments may end up pending | NHE-44 G14a-e            |
| 5 | Screenshots in `skills/.../screenshots/` are 73-byte pointers, not PNGs                     | By design (§5.4)         |
| 6 | "Tomando tiempo inusualmente largo" precedes successful script completion                   | LLM patience tuning      |

---

## Appendix A — Quick command cheatsheet

```bash
# SSH in
ssh -p 22022 -i ~/.ssh/id_rsa miguel@159.89.179.179

# Health
sudo -n -u agent bash -c "/usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs health"

# One-shot agent message
sudo -n -u agent bash -c "/usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs agent --agent readymode --message \"hola\""

# Multi-turn TUI
sudo -n -u agent bash -c "/usr/bin/node /home/agent/.npm-global/lib/node_modules/openclaw/openclaw.mjs tui --session readymode-manual-$(date +%s)"

# Tail live JSONL
sudo -n -u agent bash -c 'ls -1t /home/agent/.openclaw/logs/readymode/*.jsonl | head -1 | xargs -I{} tail -F {}'

# HALT controls
sudo -n -u agent touch  /home/agent/.openclaw/state/readymode-halt.flag    # halt
sudo -n -u agent rm -f  /home/agent/.openclaw/state/readymode-halt.flag    # resume
```

## Appendix B — Test status snapshot (2026-05-12)

| ID  | Status | Note                                          |
| --- | ------ | --------------------------------------------- |
| T1  | ✅     | smoke OK                                      |
| T2  | ✅     | testbot04 created                             |
| T3  | ✅     | testbot05 created with auto-kick              |
| T4  | ✅     | clarification path works                      |
| T5  | ⏳     | needs Discord/TUI                             |
| T6  | ⏳     | needs Discord/TUI                             |
| T7  | ⏳     | needs Discord (CSV attach)                    |
| T8  | ✅     | rejects missing attachment                    |
| T9  | ⚠️     | KB paraphrased                                |
| T10 | ⚠️     | KB paraphrased                                |
| T11 | ⚠️     | KB paraphrased                                |
| T12 | ⚠️     | KB paraphrased                                |
| T13 | ✅     | verbatim "1 (800) 694-1049 ext. 4"            |
| T14 | ✅     | "no automatizado" + phone                     |
| T15 | ⚠️     | invalid state accepted (NHE-44)               |
| T16 | ⚠️     | replies in Spanish                            |
| T17 | ⏳     | two-intent path untested                      |
| T18 | ⏳     | HALT flag path untested                       |
