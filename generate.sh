#!/bin/bash
# Usage: generate.sh <prefix>     e.g. generate.sh myapp_webhook
# Puts <prefix>_<32 random chars> on the clipboard and prints only metadata.
# The key travels through a pipe: never a variable, an argument, or stdout.
set -u

random_len=32
ttl=${APIKEY_TTL:-60}
pasteboard=${APIKEY_PASTEBOARD:-}   # empty = system clipboard; set by test.sh

prefix=${1:-}
if ! [[ $prefix =~ ^[a-z][a-z0-9]*(_[a-z0-9]+)*$ ]]; then
  echo "error: prefix must be lowercase letters/digits separated by single underscores, e.g. myapp_webhook" >&2
  exit 2
fi
expected=$(( ${#prefix} + 1 + random_len ))

open_pb='ObjC.import("AppKit");
const openPb = n => n ? $.NSPasteboard.pasteboardWithName(n) : $.NSPasteboard.generalPasteboard;'

# Reads the key from stdin. Marks it concealed/transient for clipboard managers
# and current-host-only (1) so it does not sync to other Apple devices.
copy_js="$open_pb"'
function run(a) {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  const key = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  if (key.isNil() || Number(key.length) !== Number(a[0])) throw new Error("bad key length");
  const pb = openPb(a[1]);
  pb.prepareForNewContentsWithOptions(1);
  pb.setStringForType(key, "public.utf8-plain-text");
  pb.setStringForType("", "org.nspasteboard.ConcealedType");
  pb.setStringForType("", "org.nspasteboard.TransientType");
  return String(pb.changeCount);
}'

# Holds no key: it clears only if nothing else was copied since (same changeCount).
wipe_js="$open_pb"'
function run(a) {
  delay(Number(a[0]));
  const pb = openPb(a[2]);
  if (String(pb.changeCount) === a[1]) pb.clearContents;
}'

count=$(
  { printf '%s_' "$prefix"
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$random_len"
  } | osascript -l JavaScript -e "$copy_js" "$expected" "$pasteboard" 2>/dev/null
) || { echo "error: could not write to the clipboard" >&2; exit 1; }

nohup osascript -l JavaScript -e "$wipe_js" "$ttl" "$count" "$pasteboard" >/dev/null 2>&1 </dev/null &
disown

echo "Copied to clipboard: prefix ${prefix}_, $expected characters, clears in ${ttl}s."
