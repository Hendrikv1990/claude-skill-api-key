# api-key — Claude Code skill

Generates a prefixed API key (`<prefix>_<32 random chars>`) straight onto the macOS clipboard, so the key never enters the Claude session, chat, files, or shell history.

- Key goes `/dev/urandom` → pipe → `NSPasteboard`; never a variable, argument, or stdout
- Marked concealed/transient for clipboard managers; current-host only (no Universal Clipboard sync)
- Auto-clears after 60s (`APIKEY_TTL`), unless something newer was copied

macOS only (uses `osascript` JXA).

## Sharing a key with someone else

`share.mjs` turns a key into a password-protected [Bitwarden Send](https://bitwarden.com/products/send/). You email the link and send the password through a second channel (Signal, SMS); either one alone reveals nothing. The key, the link and the password never touch stdout, a command-line argument or a file. Each one is handed to you on the clipboard in turn.

```bash
brew install bitwarden-cli && bw login     # once (EU: bw config server https://vault.bitwarden.eu first)
bash unlock.sh                             # in your own terminal; stores the session in the macOS keychain

node share.mjs myapp_webhook               # new key -> clipboard: key, then (--next) link, then (--next) password
node share.mjs --clipboard                 # share a key you have copied
node share.mjs --next                      # move the next item onto the clipboard
node share.mjs --revoke <id>               # kill the Send early
bash lock.sh                               # forget the session
```

Defaults: expires after 24h, at most 3 opens (a single open can be used up by email link scanners), text hidden until clicked, sender email hidden. `--hours`, `--opens`, and `--to <email>` (recipient verifies by emailed code instead of a password) change them.

## Install

```bash
git clone https://github.com/Hendrikv1990/claude-skill-api-key ~/.claude/skills/api-key
```

Then ask Claude Code to "generate an API key for X".

## Manual use

```bash
bash ~/.claude/skills/api-key/generate.sh myapp_webhook
```

## Test

```bash
bash ~/.claude/skills/api-key/test.sh
bash ~/.claude/skills/api-key/test-share.sh
```

Both use private named pasteboards, and `test-share.sh` uses a fake `bw`; your real clipboard and vault are untouched.

## Caveat

The clipboard isn't private — other apps running as your user can read it during the TTL.
