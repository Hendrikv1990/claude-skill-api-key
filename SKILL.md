---
name: api-key
description: Use when the user asks to generate, create, or rotate an API key, webhook secret, or bearer token for them to paste somewhere, or wants a prefixed key instead of raw openssl output.
---

# API Key

Generates a prefixed key straight onto the user's clipboard, so the key never enters the session.

## Steps

1. Choose the prefix: `<app>_<purpose>`, lowercase, short, from the current project and what the key is for. Examples: `myapp_webhook`, `billing_powerbi`. Add `live` or `test` when the user names an environment.
2. Run `bash ~/.claude/skills/api-key/generate.sh <prefix>`.
3. Relay the script's one-line result and tell the user to paste within 60 seconds.

The script is the only key generator to use, and its one-line result is all you report. A key never appears in chat, files, `.env`, or commands.

If the key must also be set somewhere, the user pastes it there themselves. To confirm it worked, ask the user to test the integration.

## Security notes

The clipboard is not private: other apps running as the user can read it. If the user asks whether the key is fully secret, say so.

Changing the script? Run `bash ~/.claude/skills/api-key/test.sh`. It uses a private pasteboard, not the real clipboard.
