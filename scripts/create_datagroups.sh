#!/bin/bash

# Generate a 256-bit AES encryption key (Base64 encoded)
TOTP_ENC_KEY=$(openssl rand -base64 32)
echo "Encryption Key: $TOTP_ENC_KEY"

# Generate a shared API key (hex encoded)
TOTP_API_KEY=$(openssl rand -hex 32)
echo "API Key: $TOTP_API_KEY"

echo ""
echo "=== SAVE BOTH VALUES SECURELY ==="
echo "The encryption key is needed to decrypt all TOTP secrets."
echo "The API key is needed in the HTTP AAA object and by external API clients."

tmsh create ltm data-group internal totp_config_dg type string
tmsh modify ltm data-group internal totp_config_dg records replace-all-with { \
    encryption_key { data "$TOTP_ENC_KEY" } \
    issuer { data "mfa-demo" } \
    api_key { data "$TOTP_API_KEY" } \
    rate_max_attempts { data "5" } \
    rate_window_seconds { data "300" } \
    enroll_rate_max_attempts { data "3" } \
    enroll_rate_window_seconds { data "600" } \
}
tmsh save sys config