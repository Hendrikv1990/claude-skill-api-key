#!/bin/bash
# Tests generate.sh against a private named pasteboard, so the real clipboard
# is never touched. Keys are checked but never printed.
set -u
dir="$(cd "$(dirname "$0")" && pwd)"
export APIKEY_PASTEBOARD="apikey-test-$$"
export APIKEY_TTL=2
fails=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

pb() { # pb <read|write|types|release> [value]
  osascript -l JavaScript \
    -e 'ObjC.import("AppKit");' \
    -e 'function run(a){const p=$.NSPasteboard.pasteboardWithName(a[0]);' \
    -e 'if(a[1]==="read"){const s=p.stringForType("public.utf8-plain-text");return s.isNil()?"":s.js}' \
    -e 'if(a[1]==="types"){return ObjC.deepUnwrap(p.types).join(" ")}' \
    -e 'if(a[1]==="write"){p.clearContents;p.setStringForType(a[2],"public.utf8-plain-text");return ""}' \
    -e 'if(a[1]==="release"){p.releaseGlobally;return ""}}' \
    "$APIKEY_PASTEBOARD" "$@"
}

out=$(bash "$dir/generate.sh" myapp_webhook 2>&1); code=$?
key=$(pb read)
[ $code -eq 0 ] && pass "valid prefix exits 0" || fail "valid prefix exits 0"
[[ $key =~ ^myapp_webhook_[A-Za-z0-9]{32}$ ]] && pass "key has prefix and 32 random chars" || fail "key format"
if [ -n "$key" ] && [[ $out != *"${key##*_}"* ]]; then pass "output has no key material"; else fail "output has no key material"; fi
[[ $out == *"myapp_webhook_"* && $out == *"46 characters"* ]] && pass "output reports prefix and length" || fail "output reports prefix and length"
[[ $(pb types) == *org.nspasteboard.ConcealedType* ]] && pass "marked concealed" || fail "marked concealed"

bash "$dir/generate.sh" myapp_webhook >/dev/null 2>&1
[ "$(pb read)" != "$key" ] && pass "keys differ between runs" || fail "keys differ between runs"

pb write sentinel >/dev/null
for bad in "" "Bad Prefix" "a;touch x" "-x" "x_" "_x" "x__y" 'a$(id)'; do
  if bash "$dir/generate.sh" "$bad" >/dev/null 2>&1; then fail "rejects '$bad'"; else pass "rejects '$bad'"; fi
done
[ "$(pb read)" = sentinel ] && pass "rejected prefix leaves clipboard alone" || fail "rejected prefix leaves clipboard alone"

bash "$dir/generate.sh" wipe_me >/dev/null 2>&1
sleep 3
[ -z "$(pb read)" ] && pass "clipboard wiped after TTL" || fail "clipboard wiped after TTL"

bash "$dir/generate.sh" keep_me >/dev/null 2>&1
pb write something-else >/dev/null
sleep 3
[ "$(pb read)" = something-else ] && pass "newer copy survives the wipe" || fail "newer copy survives the wipe"

pb release >/dev/null
[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
