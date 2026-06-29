#!/bin/bash
# /config/totp/totp_enroll.sh
# Triggered by /config/user_alert.conf when TOTP_ENROLL_TRIGGER is detected.
#
# Flow:
#   1. Reads username(s) from recent TOTP_ENROLL_TRIGGER entries in /var/log/ltm
#   2. Queries the TOTP verification API to retrieve the cached encrypted secret
#   3. Commits the secret to the internal data group via tmsh
#   4. Saves the config to persist the change and trigger configsync
#
# The encrypted secret is NEVER logged - only the username appears in the log.
# The secret is retrieved via a clean HTTP API call, avoiding any data
# corruption from syslog/shell/grep processing of binary/Base64 data.

LOG_TAG="totp-enroll"
DATAGROUP="totp_secrets_dg"
LOGFILE="/var/log/ltm"
API_HOST="totp-api.mfa-demo.local"
API_PORT="80"

log_msg() { logger -p local0.info -t "$LOG_TAG" "$1"; }
log_err() { logger -p local0.err  -t "$LOG_TAG" "$1"; }

# Read the API key from the data group
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}')
if [ -z "$API_KEY" ]; then
    log_err "Cannot read API key from totp_config_dg"
    exit 1
fi

# Use a lock file to prevent concurrent execution
LOCK_FILE="/var/run/totp_enroll.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log_msg "Already running, skipping"
    exit 0
fi

# Use a marker file to track which log lines have been processed
MARKER_FILE="/var/tmp/.totp_enroll_marker"
if [ -f "$MARKER_FILE" ]; then
    LAST_PROCESSED=$(cat "$MARKER_FILE")
else
    LAST_PROCESSED=0
fi

# Detect log rotation by checking file inode
CURRENT_INODE=$(stat -c %i "$LOGFILE" 2>/dev/null)
MARKER_INODE=""
if [ -f "${MARKER_FILE}.inode" ]; then
    MARKER_INODE=$(cat "${MARKER_FILE}.inode")
fi
if [ "$CURRENT_INODE" != "$MARKER_INODE" ]; then
    LAST_PROCESSED=0
    echo "$CURRENT_INODE" > "${MARKER_FILE}.inode"
fi

# Check if there are new lines to process
TOTAL_LINES=$(wc -l < "$LOGFILE")
if [ "$TOTAL_LINES" -le "$LAST_PROCESSED" ]; then
    exit 0
fi

PROCESSED=0

# Extract usernames from new TOTP_ENROLL_TRIGGER log lines
tail -n +$((LAST_PROCESSED + 1)) "$LOGFILE" | grep "TOTP_ENROLL_TRIGGER:" | while IFS= read -r line; do
    # Extract username from: TOTP_ENROLL_TRIGGER:<username>
    USERNAME=$(echo "$line" | grep -oP 'TOTP_ENROLL_TRIGGER:\K[a-zA-Z0-9._@-]+')
    if [ -z "$USERNAME" ]; then
        continue
    fi

    # Normalize to lowercase
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

    # Check if already in the data group
    EXISTING=$(tmsh list ltm data-group internal "$DATAGROUP" records 2>/dev/null | grep "${USERNAME}")
    if [ -n "$EXISTING" ]; then
        log_msg "$USERNAME already in data group, skipping"
        continue
    fi

    # Query the verification API to get the cached encrypted secret
    RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" \
        "http://${API_HOST}:${API_PORT}/api/v1/export-secret?username=${USERNAME}" 2>/dev/null)

    if [ -z "$RESPONSE" ]; then
        log_err "Empty response from API for $USERNAME"
        continue
    fi

    # Verify the API returned a successful result
    if ! echo "$RESPONSE" | grep -q '"result":"ok"'; then
        log_err "API did not return secret for $USERNAME: $RESPONSE"
        continue
    fi

    # Extract the encrypted secret from the JSON response
    SECRET=$(echo "$RESPONSE" | grep -oP '"secret":"\K[^"]+')
    if [ -z "$SECRET" ]; then
        log_err "Could not parse secret from API response for $USERNAME"
        continue
    fi

    # Commit to the internal data group
    tmsh modify ltm data-group internal "$DATAGROUP" \
        records add \{ "${USERNAME}" \{ data "${SECRET}" \} \} 2>/dev/null

    if [ $? -ne 0 ]; then
        # Record may already exist - try modify
        tmsh modify ltm data-group internal "$DATAGROUP" \
            records modify \{ "${USERNAME}" \{ data "${SECRET}" \} \} 2>/dev/null

        if [ $? -ne 0 ]; then
            log_err "Failed to commit secret for $USERNAME"
            continue
        fi
    fi

    log_msg "Committed secret for $USERNAME to data group"
    PROCESSED=$((PROCESSED + 1))
done

# Update the marker to current line count
echo "$TOTAL_LINES" > "$MARKER_FILE"

# Save config if we processed any enrollments
if [ "$PROCESSED" -gt 0 ]; then
    tmsh save sys config partitions { Common } 2>/dev/null
    log_msg "Config saved after $PROCESSED enrollment(s)"
fi