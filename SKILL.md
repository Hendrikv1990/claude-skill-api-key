---
name: api-key
description: Use when the user asks to generate, create, or rotate an API key, webhook secret, or bearer token for them to paste somewhere, wants a prefixed key instead of raw openssl output, or wants to share a key with someone else safely (Bitwarden Send).
---

# API Key

Generates a prefixed key straight onto the user's clipboard, so the key never enters the session.

## Steps

1. Choose the prefix: `<app>_<purpose>`, lowercase, short, from the current project and what the key is for. Examples: `myapp_webhook`, `billing_powerbi`. Add `live` or `test` when the user names an environment.
2. Run `bash ~/.claude/skills/api-key/generate.sh <prefix>`.
3. Relay the script's one-line result and tell the user to paste within 60 seconds.

The script is the only key generator to use, and its one-line result is all you report. A key never appears in chat, files, `.env`, or commands.

If the key must also be set somewhere, the user pastes it there themselves. To confirm it worked, ask the user to test the integration.

## Sharing a key with someone else

Use when the user wants to send a key to another person. It creates a password-protected Bitwarden Send: the link goes by email, the password by a second channel (Signal, SMS, phone). Either one alone is useless.

1. New key: `node ~/.claude/skills/api-key/share.mjs <prefix>`. Existing key: ask the user to copy it, then `node ~/.claude/skills/api-key/share.mjs --clipboard`.
   Options: `--hours N` (default 24), `--opens N` (default 3; keep above 1, email scanners can use up an open), `--to <email>` (recipient verifies by emailed code instead of a password; may need a paid plan).
2. Relay the script's result. The clipboard now holds the first item; the script names what comes next.
3. When the user says they pasted it, run `node ~/.claude/skills/api-key/share.mjs --next`. Repeat until it says the queue is empty. Order: key (new keys only), link, password.
4. To kill a Send early: `node ~/.claude/skills/api-key/share.mjs --revoke <id>` (the id is in the result).

If it says Bitwarden is locked, ask the user to run `bash ~/.claude/skills/api-key/unlock.sh` **in their own terminal**, not with `!`: the session key must not enter this session. `lock.sh` undoes it. First use needs `brew install bitwarden-cli` and `bw login` (EU accounts: `bw config server https://vault.bitwarden.eu` first).

Never send the email or message yourself, and never ask for the link or password: they are as sensitive as the key.

## Security notes

The clipboard is not private: other apps running as the user can read it. If the user asks whether the key is fully secret, say so.

While a share is in progress, the items not yet on the clipboard wait in a private named pasteboard for at most 15 minutes. Like the clipboard, other apps running as the user could read it.

Changing the scripts? Run `bash ~/.claude/skills/api-key/test.sh` and `bash ~/.claude/skills/api-key/test-share.sh`. They use private pasteboards and a fake `bw`, not the real clipboard or vault.
