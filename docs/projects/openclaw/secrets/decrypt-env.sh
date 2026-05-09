#!/usr/bin/env bash
# decrypt-env.sh — Decrypt the three OpenClaw production secret files from
# their .enc artifacts into the live filesystem locations with the correct
# owner and permissions.
#
# Usage:
#   sudo ./decrypt-env.sh             # writes live files (DESTRUCTIVE)
#   sudo ./decrypt-env.sh --dry-run   # writes to /tmp/<name>.decrypt-test
#                                     # and diffs against the live file
#
# Prereqs on the host:
#   - sops on PATH (>=3.12)
#   - age key at /root/.config/sops/age/keys.txt (chmod 600 root:root)
#   - The 3 .enc files alongside this script
#
# This script does NOT restart any service. Restart order is documented in
# rotate-secrets.sh. Run that playbook after a rotation, not after a routine
# decrypt.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must be run as root (use sudo)" >&2
  exit 1
fi

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/root/.config/sops/age/keys.txt}"

if [[ ! -r "$SOPS_AGE_KEY_FILE" ]]; then
  echo "ERROR: cannot read age key at $SOPS_AGE_KEY_FILE" >&2
  exit 2
fi

if ! command -v sops >/dev/null 2>&1; then
  echo "ERROR: sops not on PATH" >&2
  exit 3
fi

# Triples: enc_basename | live_path | owner:group | mode
TARGETS=(
  "openclaw.env.enc|/etc/openclaw.env|root:root|600"
  "aurora.env.enc|/home/agent/.openclaw/workspace/aurora/.env|agent:agent|600"
  "openclaw.json.enc|/home/agent/.openclaw/openclaw.json|agent:agent|600"
)

decrypt_one() {
  local enc_path="$1" live_path="$2" owner="$3" mode="$4"

  if [[ ! -f "$enc_path" ]]; then
    echo "ERROR: encrypted source missing: $enc_path" >&2
    return 4
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local test_out="/tmp/$(basename "$live_path").decrypt-test"
    sops -d --input-type binary --output-type binary "$enc_path" > "$test_out"
    chmod 600 "$test_out"
    echo "--- dry-run: $live_path"
    if [[ -f "$live_path" ]]; then
      if diff -q "$test_out" "$live_path" >/dev/null 2>&1; then
        echo "    MATCH (decrypted == live)"
      else
        echo "    DIFFER (decrypted != live)"
        diff "$live_path" "$test_out" | head -20 || true
      fi
    else
      echo "    (no live file present yet)"
    fi
    echo "    wrote $test_out"
    return 0
  fi

  # Real run: write to a tmp file in the SAME dir then atomic rename.
  local target_dir
  target_dir="$(dirname "$live_path")"
  mkdir -p "$target_dir"
  local tmp_path
  tmp_path="$(mktemp "${target_dir}/.$(basename "$live_path").XXXXXX")"
  trap 'rm -f "$tmp_path"' RETURN

  sops -d --input-type binary --output-type binary "$enc_path" > "$tmp_path"
  chown "$owner" "$tmp_path"
  chmod "$mode" "$tmp_path"
  mv -f "$tmp_path" "$live_path"
  trap - RETURN
  echo "wrote $live_path ($owner $mode)"
}

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r enc live owner mode <<< "$entry"
  decrypt_one "${SCRIPT_DIR}/${enc}" "$live" "$owner" "$mode"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN complete. No live files modified."
else
  echo "Decrypt complete. Restart services per rotate-secrets.sh playbook only if rotating."
fi
