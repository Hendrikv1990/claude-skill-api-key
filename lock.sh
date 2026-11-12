#!/bin/bash
# Removes the stored Bitwarden session and locks the vault.
svc=${APIKEY_KEYCHAIN_SERVICE:-apikey-bw-session}
security delete-generic-password -s "$svc" >/dev/null 2>&1
bw lock >/dev/null 2>&1
echo "Locked. Session removed from the keychain."
