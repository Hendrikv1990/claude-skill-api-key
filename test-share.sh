#!/bin/bash
# Tests share.mjs with a fake `bw`, private pasteboards and a test keychain entry.
# Never touches the real clipboard or vault; secrets are compared, never printed.
set -u
dir="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d)
export APIKEY_PASTEBOARD="apikey-share-test-$$"
export APIKEY_QUEUE_PASTEBOARD="apikey-share-queue-test-$$"
export APIKEY_KEYCHAIN_SERVICE="apikey-bw-session-test-$$"
export APIKEY_TTL=30 APIKEY_QUEUE_TTL=60
export APIKEY_BW="$tmp/bw" FAKE_LOG="$tmp"
fails=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

cat > "$tmp/bw" <<'FAKE'
#!/bin/bash
printf '%s\n' "$BW_SESSION" > "$FAKE_LOG/session"
case "$1 $2" in
  "status "*) echo "{\"status\":\"${FAKE_STATUS:-unlocked}\"}";;
  "send create") printf '%s ' "$@" > "$FAKE_LOG/argv"; base64 -d > "$FAKE_LOG/req.json"
    [ -n "${FAKE_FAIL:-}" ] && exit 1
    echo '{"id":"0b1c2d3e-0000-4000-8000-000000000001","accessUrl":"https://send.bitwarden.example/#/abc/LINKSECRET'$$'"}';;
  "send delete") printf '%s ' "$@" > "$FAKE_LOG/deleted";;
esac
FAKE
chmod +x "$tmp/bw"

pb() { osascript -l JavaScript -e 'ObjC.import("AppKit");' \
  -e 'function run(a){const p=$.NSPasteboard.pasteboardWithName(a[0]);' \
  -e 'if(a[1]==="read"){const s=p.stringForType("public.utf8-plain-text");return s.isNil()?"":s.js}' \
  -e 'if(a[1]==="write"){p.clearContents;p.setStringForType(a[2],"public.utf8-plain-text");return ""}' \
  -e 'if(a[1]==="release"){p.releaseGlobally;return ""}}' "$@"; }
clip() { pb "$APIKEY_PASTEBOARD" read; }
req() { node -e 'const r=require(process.argv[1]); const k=process.argv[2].split("."); let v=r; for (const p of k) v=v?.[p]; console.log(v===null?"null":Array.isArray(v)?v.join(","):v)' "$tmp/req.json" "$1"; }
share() { node "$dir/share.mjs" "$@"; }

# No session in the keychain yet.
out=$(share myapp_webhook 2>&1); code=$?
check "no stored session: refuses and points to unlock.sh" '[ $code -ne 0 ] && [[ $out == *unlock.sh* ]]'
printf 'add-generic-password -U -s %s -a test -w dummy-session\n' "$APIKEY_KEYCHAIN_SERVICE" | security -i

out=$(FAKE_STATUS=locked share myapp_webhook 2>&1); code=$?
check "locked vault: refuses, no Send created" '[ $code -ne 0 ] && [[ $out == *unlock.sh* ]] && [ ! -f "$tmp/req.json" ]'
check "bad prefix rejected" '! share "a;id" >/dev/null 2>&1'
check "bad --opens rejected" '! share myapp_webhook --opens 0 >/dev/null 2>&1'

# Generate + share.
out=$(share myapp_webhook 2>&1); code=$?
key=$(req text.text); pw=$(req password); url="https://send.bitwarden.example/#/abc/LINKSECRET"
check "generate exits 0" '[ $code -eq 0 ]'
check "key format" '[[ $key =~ ^myapp_webhook_[A-Za-z0-9]{32}$ ]]'
check "session passed from keychain via env" '[ "$(cat "$tmp/session")" = dummy-session ]'
check "Send: hidden text, 3 opens, hide email" '[ "$(req text.hidden)" = true ] && [ "$(req maxAccessCount)" = 3 ] && [ "$(req hideEmail)" = true ]'
check "Send: 24-char password, no emails" '[[ $pw =~ ^[A-Za-z0-9]{24}$ ]] && [ "$(req emails)" = null ]'
check "Send: expires ~24h from now" 'node -e "const d=new Date(process.argv[1])-Date.now(); process.exit(Math.abs(d-864e5)<6e4?0:1)" "$(req expirationDate)"'
check "argv carries no secret" '! grep -qe "$key" -e "$pw" "$tmp/argv"'
check "output has no key, password or link" '[[ $out != *"${key##*_}"* && $out != *"$pw"* && $out != *LINKSECRET* ]]'
check "output reports id, protection, opens" '[[ $out == *0b1c2d3e* && $out == *password-protected* && $out == *"3 opens"* ]]'
check "clipboard 1: the key" '[ "$(clip)" = "$key" ]'
out=$(share --next 2>&1)
check "clipboard 2: the link" '[[ "$(clip)" == ${url}* ]] && [[ $out != *LINKSECRET* ]]'
share --next >/dev/null 2>&1
check "clipboard 3: the password" '[ "$(clip)" = "$pw" ]'
check "queue then empty" '[[ $(share --next 2>&1) == "Nothing queued." ]]'

# Share what is on the clipboard.
rm -f "$tmp/req.json"; pb "$APIKEY_PASTEBOARD" write "existing-secret-$$" >/dev/null
out=$(share --clipboard --hours 2 --opens 1 2>&1)
check "clipboard mode sends the clipboard contents" '[ "$(req text.text)" = "existing-secret-$$" ] && [ "$(req maxAccessCount)" = 1 ]'
check "clipboard mode: first item is the link" '[[ "$(clip)" == ${url}* ]]'
check "clipboard mode output has no secret" '[[ $out != *existing-secret* ]]'
share --next >/dev/null; share --next >/dev/null 2>&1

# Email verification instead of a password.
out=$(share myapp_test --to someone@example.com 2>&1)
check "--to: emails set, no password" '[ "$(req emails)" = someone@example.com ] && [ "$(req password)" = null ]'
share --next >/dev/null 2>&1
check "--to: queue has no password item" '[[ $(share --next 2>&1) == "Nothing queued." ]]'

out=$(FAKE_FAIL=1 share myapp_webhook 2>&1); code=$?
check "Bitwarden failure: nonzero, no secret in output" '[ $code -ne 0 ] && [[ $out != *myapp_webhook_* ]]'

share --revoke 0b1c2d3e-0000-4000-8000-000000000001 >/dev/null 2>&1
check "revoke calls send delete" 'grep -q "send delete 0b1c2d3e" "$tmp/deleted"'

security delete-generic-password -s "$APIKEY_KEYCHAIN_SERVICE" >/dev/null 2>&1
pb "$APIKEY_PASTEBOARD" release >/dev/null; pb "$APIKEY_QUEUE_PASTEBOARD" release >/dev/null
rm -rf "$tmp"
[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
