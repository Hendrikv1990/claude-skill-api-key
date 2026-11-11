# api-key — Claude Code skill

Generates a prefixed API key (`<prefix>_<32 random chars>`) straight onto the macOS clipboard, so the key never enters the Claude session, chat, files, or shell history.

- Key goes `/dev/urandom` → pipe → `NSPasteboard`; never a variable, argument, or stdout
- Marked concealed/transient for clipboard managers; current-host only (no Universal Clipboard sync)
- Auto-clears after 60s (`APIKEY_TTL`), unless something newer was copied

macOS only (uses `osascript` JXA).

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
```

Uses a private named pasteboard; your real clipboard is untouched.

## Caveat

The clipboard isn't private — other apps running as your user can read it during the TTL.
