#!/bin/bash
# /config/totp/totp_unenroll.sh
# Triggered by /config/user_alert.conf when TOTP_UNENROLL_TRIGGER is detected.
# Reads username from the log and removes the record from the data group.

LOG_TAG="totp-unenroll"
DATAGROUP="totp_secrets_dg"
LOGFILE="/var/log/ltm"

log_msg() { logger -p local0.info -t "$LOG_TAG" "$1"; }
log_err() { logger -p local0.err  -t "$LOG_TAG" "$1"; }

# Use a lock file to prevent concurrent execution
LOCK_FILE="/var/run/totp_unenroll.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log_msg "Already running, skipping"
    exit 0
fi

# Use a marker file to track processed lines
MARKER_FILE="/var/tmp/.totp_unenroll_marker"
if [ -f "$MARKER_FILE" ]; then
    LAST_PROCESSED=$(cat "$MARKER_FILE")
else
    LAST_PROCESSED=0
fi

# Detect log rotation
CURRENT_INODE=$(stat -c %i "$LOGFILE" 2>/dev/null)
MARKER_INODE=""
if [ -f "${MARKER_FILE}.inode" ]; then
    MARKER_INODE=$(cat "${MARKER_FILE}.inode")
fi
if [ "$CURRENT_INODE" != "$MARKER_INODE" ]; then
    LAST_PROCESSED=0
    echo "$CURRENT_INODE" > "${MARKER_FILE}.inode"
fi

# Check for new lines
TOTAL_LINES=$(wc -l < "$LOGFILE")
if [ "$TOTAL_LINES" -le "$LAST_PROCESSED" ]; then
    exit 0
fi

PROCESSED=0

# Extract usernames from TOTP_UNENROLL_TRIGGER log lines
tail -n +$((LAST_PROCESSED + 1)) "$LOGFILE" | grep "TOTP_UNENROLL_TRIGGER:" | while IFS= read -r line; do
    # Extract username
    USERNAME=$(echo "$line" | grep -oP 'TOTP_UNENROLL_TRIGGER:\K[a-zA-Z0-9._@-]+')
    if [ -z "$USERNAME" ]; then
        continue
    fi

    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]')

    # Check if the record exists in the data group
    EXISTING=$(tmsh list ltm data-group internal "$DATAGROUP" records 2>/dev/null | grep "${USERNAME}")
    if [ -z "$EXISTING" ]; then
        log_msg "$USERNAME not found in data group, skipping"
        continue
    fi

    # Remove from the data group
    tmsh modify ltm data-group internal "$DATAGROUP" \
        records delete \{ "${USERNAME}" \} 2>/dev/null

    if [ $? -ne 0 ]; then
        log_err "Failed to remove $USERNAME from data group"
        continue
    fi

    log_msg "Removed $USERNAME from data group"
    PROCESSED=$((PROCESSED + 1))
done

# Update marker
echo "$TOTAL_LINES" > "$MARKER_FILE"

# Save config if we processed any unenrollments
if [ "$PROCESSED" -gt 0 ]; then
    tmsh save sys config partitions { Common } 2>/dev/null
    log_msg "Config saved after $PROCESSED unenrollment(s)"
fi