#!/bin/bash
# Run in YOUR OWN terminal (not through Claude): unlocks Bitwarden and stores the session key in the
# macOS keychain for share.mjs. The session key never reaches Claude, stdout or a process argument.
set -eu
svc=${APIKEY_KEYCHAIN_SERVICE:-apikey-bw-session}
command -v bw >/dev/null || { echo "Install the Bitwarden CLI first: brew install bitwarden-cli" >&2; exit 1; }
status=$(bw status | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p')
if [ "$status" = unauthenticated ]; then
  echo "Not logged in. EU account? First: bw config server https://vault.bitwarden.eu" >&2
  echo "Then: bw login   (and run this script again)" >&2
  exit 1
fi
session=$(bw unlock --raw)
[ -n "$session" ] || { echo "unlock failed" >&2; exit 1; }
# security -i reads the command from stdin, so the session key is not visible in `ps`.
printf 'add-generic-password -U -s %s -a %s -w %s\n' "$svc" "$USER" "$session" | security -i
unset session
echo "Unlocked. share.mjs can create Sends until you run lock.sh (or Bitwarden logs you out)."
