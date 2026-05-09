#!/usr/bin/env bash
# rotate-secrets.sh — PLAYBOOK (not fully automated) for rotating the
# OpenClaw production secrets that are managed via sops+age.
#
# This script just prints the steps. Read it, follow it manually, and only
# proceed each step after the previous one is verified.
#
# Window 1 (setup) — DONE in branch openclaw/sops-secrets:
#   - age + sops installed on 159.89.179.179
#   - master age key at /root/.config/sops/age/keys.txt (chmod 600 root:root)
#   - .enc artifacts committed under docs/projects/openclaw/secrets/
#   - decrypt-env.sh + this rotate playbook committed
#   - originals untouched, no service restarted
#
# Window 2 (rotation + go-live) — what this playbook covers below.

cat <<'PLAYBOOK'
================================================================================
OpenClaw secret rotation playbook (Window 2)
================================================================================

PRECONDITIONS
  - You have explicit go-ahead from Miguel for downtime (~5-10 min).
  - You are on 159.89.179.179 with sudo.
  - The branch openclaw/sops-secrets is checked out somewhere accessible OR
    you have sops/age installed locally with the master private key.
  - You have the admin/console URLs ready (see below).

--------------------------------------------------------------------------------
STEP 0 — Backup the current originals (always)
--------------------------------------------------------------------------------
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  sudo mkdir -p /root/secret-backups/$TS
  sudo cp -a /etc/openclaw.env                                /root/secret-backups/$TS/
  sudo cp -a /home/agent/.openclaw/workspace/aurora/.env      /root/secret-backups/$TS/aurora.env
  sudo cp -a /home/agent/.openclaw/openclaw.json              /root/secret-backups/$TS/
  sudo chmod -R 600 /root/secret-backups/$TS

--------------------------------------------------------------------------------
STEP 1 — Rotate each secret value at its origin
--------------------------------------------------------------------------------
Rotate ONE-BY-ONE so a failure is easy to localise. For each, write the new
value into a scratch file you'll feed into sops in step 2.

/etc/openclaw.env  (14 vars):
  OPENAI_API_KEY              -> https://platform.openai.com/api-keys
  OPENCLAW_GATEWAY_TOKEN      -> internal: regenerate via
                                 `openclaw gateway rotate-token` or equivalent;
                                 keep both old+new live during cutover if you can
  OPENCLAW_HOOK_TOKEN         -> internal: same as above
  OPENCLAW_DISABLE_BONJOUR    -> static toggle, do not rotate
  PATH                        -> static, do not rotate
  META_GRAPH_VERSION          -> static, do not rotate
  META_AD_ACCOUNT_ID          -> static, do not rotate
  META_ACCESS_TOKEN           -> https://developers.facebook.com/tools/explorer
  META_ADS_ACCESS_TOKEN       -> same as META_ACCESS_TOKEN (long-lived sys-user)
  DATABASE_URL                -> rotate Postgres password, then update conn URI
                                 (psql: ALTER USER ... WITH PASSWORD ...)
  CLAW_DATABASE_URL           -> same DB cluster, same procedure
  READYMODE_URL               -> only if endpoint changes
  READYMODE_USERNAME          -> ReadyMode admin dashboard
  READYMODE_PASSWORD          -> ReadyMode admin dashboard

/home/agent/.openclaw/workspace/aurora/.env  (31 vars, key ones):
  DATABASE_URL                -> Postgres (same as above if shared)
  CLW_API_KEY                 -> internal claw token
  OCR_API_KEY                 -> OCR provider console
  SESSION_SECRET, AUTH_SECRET -> regenerate: `openssl rand -hex 32`
  FINANCE_AUTOMATION_TOKEN    -> internal finance agent token
  Other NEXT_PUBLIC_*, *_TIMEOUT_*, *_PATH, NODE_ENV  -> static config, do not rotate
  OPENCLAW_*_AGENT_ID         -> static, do not rotate

/home/agent/.openclaw/openclaw.json  (top-level keys):
  meta, env, wizard, browser, agents, tools, bindings, messages,
  commands, session, cron, hooks, channels, discovery, gateway,
  skills, plugins
  Sensitive material lives mainly under:
    - channels (Discord ReadyMode bot token)         -> Discord Developer Portal
    - gateway  (gateway tokens)                      -> internal regeneration
    - tools    (any per-tool creds, eg Anthropic/OpenAI/R2/Cloudflare)
                                                     -> respective consoles
  Edit in place via:
      sudo SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
        sops docs/projects/openclaw/secrets/openclaw.json.enc
  (sops will open $EDITOR with the decrypted blob; save+exit re-encrypts.)

--------------------------------------------------------------------------------
STEP 2 — Update the .enc artifacts in the openclaw/sops-secrets branch
--------------------------------------------------------------------------------
For each .enc file, open with sops, paste new values, save:

  cd <repo>/docs/projects/openclaw/secrets
  sudo SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops openclaw.env.enc
  sudo SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops aurora.env.enc
  sudo SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt sops openclaw.json.enc

Verify each round-trips:

  for f in openclaw.env.enc aurora.env.enc openclaw.json.enc; do
    sudo SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
      sops -d --input-type binary --output-type binary "$f" | head -c 200
    echo
  done

Commit + push (still on openclaw/sops-secrets, no PR):
  git add openclaw.env.enc aurora.env.enc openclaw.json.enc
  git commit -m "[openclaw][sops] Rotate secrets <YYYY-MM-DD>"
  git push origin openclaw/sops-secrets

--------------------------------------------------------------------------------
STEP 3 — Deploy: decrypt-env.sh on the server
--------------------------------------------------------------------------------
  cd <repo>/docs/projects/openclaw/secrets
  sudo ./decrypt-env.sh --dry-run    # confirms diffs vs live (expected: DIFFER on rotated vars)
  sudo ./decrypt-env.sh              # writes new live files

Verify perms post-write:
  sudo stat -c '%n %U:%G %a' \
    /etc/openclaw.env \
    /home/agent/.openclaw/workspace/aurora/.env \
    /home/agent/.openclaw/openclaw.json

--------------------------------------------------------------------------------
STEP 4 — Restart services in this exact sequential order
--------------------------------------------------------------------------------
Wait for each to settle (~5s) before the next:

  sudo systemctl restart openclaw-bg-dispatcher
  sudo systemctl restart openclaw-bg-worker
  sudo systemctl restart openclaw-owner-policy
  sudo systemctl restart aurora
  sudo systemctl restart openclaw-readymode-probe
  sudo systemctl restart openclaw-readymode-restart-scanner
  sudo systemctl restart openclaw-gateway

--------------------------------------------------------------------------------
STEP 5 — Verify
--------------------------------------------------------------------------------
  for s in openclaw-bg-dispatcher openclaw-bg-worker openclaw-owner-policy \
           aurora openclaw-readymode-probe openclaw-readymode-restart-scanner \
           openclaw-gateway; do
    printf '%-40s ' "$s"
    systemctl is-active "$s"
  done

  # last 50 lines per service, look for auth/connection errors:
  for s in openclaw-bg-dispatcher openclaw-bg-worker openclaw-owner-policy \
           aurora openclaw-readymode-probe openclaw-readymode-restart-scanner \
           openclaw-gateway; do
    echo "===== $s ====="
    sudo journalctl -u "$s" -n 50 --no-pager
  done

  # Functional smoke (whichever applies):
  curl -fsS http://localhost:<gateway-port>/healthz   # gateway
  # Discord: send a test ping in the ReadyMode channel and confirm bot replies
  # ReadyMode: trigger a probe run and check journalctl

--------------------------------------------------------------------------------
STEP 6 — Rollback (if anything is wrong)
--------------------------------------------------------------------------------
  sudo systemctl stop openclaw-gateway openclaw-readymode-restart-scanner \
       openclaw-readymode-probe aurora openclaw-owner-policy \
       openclaw-bg-worker openclaw-bg-dispatcher
  sudo cp -a /root/secret-backups/$TS/openclaw.env  /etc/openclaw.env
  sudo cp -a /root/secret-backups/$TS/aurora.env    /home/agent/.openclaw/workspace/aurora/.env
  sudo cp -a /root/secret-backups/$TS/openclaw.json /home/agent/.openclaw/openclaw.json
  sudo chown root:root /etc/openclaw.env && sudo chmod 600 /etc/openclaw.env
  sudo chown agent:agent /home/agent/.openclaw/workspace/aurora/.env \
       /home/agent/.openclaw/openclaw.json
  sudo chmod 600 /home/agent/.openclaw/workspace/aurora/.env \
       /home/agent/.openclaw/openclaw.json
  # Restart services in the same order as Step 4.

--------------------------------------------------------------------------------
STEP 7 — Post-rotation hygiene
--------------------------------------------------------------------------------
  - Revoke the OLD secret values at each provider (don't just rotate, kill old).
  - Update the paper break-glass copy ONLY if the master age private key
    itself was rotated (it usually isn't during a value rotation).
  - Note the rotation date+who in /root/secret-backups/$TS/NOTES.txt
================================================================================
PLAYBOOK
