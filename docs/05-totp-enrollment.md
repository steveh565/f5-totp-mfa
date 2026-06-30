# 05 - TOTP Enrollment

This section covers the complete TOTP enrollment infrastructure including data groups, encryption, alert scripts, iRules, iFile, virtual server, and the enrollment access policy.

---

## Enrollment Architecture Overview

The enrollment process involves multiple components working together:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Enrollment Flow                                   │
└─────────────────────────────────────────────────────────────────────────────┘

     User                    BIG-IP                         Authenticator
       │                        │                                 │
       │  1. Access /enroll     │                                 │
       ├───────────────────────►│                                 │
       │                        │                                 │
       │  2. Login prompt       │                                 │
       │◄───────────────────────┤                                 │
       │                        │                                 │
       │  3. Credentials        │                                 │
       ├───────────────────────►│                                 │
       │                        │                                 │
       │                        │ 4. Validate (LocalDB/AD)        │
       │                        ├──────────────────┐              │
       │                        │◄─────────────────┘              │
       │                        │                                 │
       │  5. QR Code Page       │                                 │
       │◄───────────────────────┤                                 │
       │                        │                                 │
       │  6. Scan QR            │                                 │
       ├────────────────────────┼────────────────────────────────►│
       │                        │                                 │
       │  7. Confirm code       │                                 │
       ├───────────────────────►│                                 │
       │                        │                                 │
       │                        │ 8. Verify code                  │
       │                        ├──────────────────┐              │
       │                        │◄─────────────────┘              │
       │                        │                                 │
       │                        │ 9. Store secret                 │
       │                        │    (subtable + DG)              │
       │                        ├──────────────────┐              │
       │                        │◄─────────────────┘              │
       │                        │                                 │
       │  10. Success           │                                 │
       │◄───────────────────────┤                                 │
       │                        │                                 │
```

### Component Summary

| Component | Purpose |
|-----------|---------|
| totp_config_dg | Configuration parameters (issuer, encryption key, rate limits) |
| totp_secrets_dg | Persistent storage of encrypted TOTP secrets |
| totp_users subtable | Runtime storage for fast lookups |
| irule_totp_shared | Shared procedures (TOTP generation, encryption, validation) |
| irule_totp_enroll | Enrollment page generation and processing |
| qrcode_js iFile | QR code generation JavaScript library |
| totp_enroll.sh | Alert script for DG persistence |
| vs_totp_enroll | Enrollment virtual server |
| ap_totp_enroll | Enrollment access policy |

---

## Data Groups

### Configuration Data Group

The `totp_config_dg` data group stores all configurable parameters:

```bash
# Generate secure keys first
TOTP_ENC_KEY=$(openssl rand -base64 32 | tr -d '\n' | cut -c1-32)
TOTP_API_KEY=$(openssl rand -hex 32)

echo "Encryption Key: $TOTP_ENC_KEY"
echo "API Key: $TOTP_API_KEY"
```

> **Important:** Save these keys securely. The encryption key protects all stored TOTP secrets.

```bash
tmsh create ltm data-group internal totp_config_dg type string records add {
    encryption_key { data "$TOTP_ENC_KEY" }
    issuer { data "MFA Demo" }
    api_key { data "$TOTP_API_KEY" }
    secret_length { data "32" }
    code_length { data "6" }
    time_step { data "30" }
    time_skew { data "1" }
    rate_max_attempts { data "5" }
    rate_window_seconds { data "300" }
    enroll_rate_max_attempts { data "3" }
    enroll_rate_window_seconds { data "600" }
    encrypt_secrets { data "1" }
}
```

### Configuration Parameters Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| encryption_key | (generated) | 32-character AES-256 encryption key |
| issuer | MFA Demo | Display name in authenticator app |
| api_key | (generated) | API authentication key |
| secret_length | 32 | Base32 secret length (characters) |
| code_length | 6 | TOTP code length (digits) |
| time_step | 30 | TOTP interval (seconds) |
| time_skew | 1 | Allowed time drift (±intervals) |
| rate_max_attempts | 5 | Verification attempts before lockout |
| rate_window_seconds | 300 | Verification lockout window (seconds) |
| enroll_rate_max_attempts | 3 | Enrollment attempts before lockout |
| enroll_rate_window_seconds | 600 | Enrollment lockout window (seconds) |
| encrypt_secrets | 1 | Enable secret encryption (1=yes, 0=no) |

### Secrets Data Group

The `totp_secrets_dg` data group provides persistent storage for enrolled user secrets:

```bash
tmsh create ltm data-group internal totp_secrets_dg type string
```

This data group starts empty. Secrets are added automatically during enrollment via the alert script mechanism.

### Verify Data Groups

```bash
# List configuration
tmsh list ltm data-group internal totp_config_dg

# List secrets (initially empty)
tmsh list ltm data-group internal totp_secrets_dg
```

---

## Secret Encryption

TOTP secrets are encrypted using AES-256-ECB before storage. This protects secrets at rest in the data group.

### Encryption Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Plain Secret │ ──► │  AES-256-ECB │ ──► │  Encrypted   │
│ (Base32)     │     │  Encryption  │     │  (Base64)    │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ encryption_  │
                    │ key (32 chr) │
                    └──────────────┘
```

### Encryption Implementation

The encryption is handled by `irule_totp_shared` procedures:

- `encrypt_secret` — Encrypts plaintext secret for storage
- `decrypt_secret` — Decrypts stored secret for verification

> **Note:** TMOS Tcl uses `aes-256-ecb` cipher. The key must be exactly 32 characters.

### Disabling Encryption (Not Recommended)

For troubleshooting only, encryption can be disabled:

```bash
tmsh modify ltm data-group internal totp_config_dg records modify {
    encrypt_secrets { data "0" }
}
```

> **Warning:** Disabling encryption stores secrets in plaintext. Not recommended for production.

---

## Alert Scripts

Alert scripts provide persistence by committing secrets from the runtime subtable to the data group. This mechanism survives TMM restarts and enables HA synchronization.

### How Alert Scripts Work

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Alert Script Mechanism                               │
└─────────────────────────────────────────────────────────────────────────────┘

  iRule                    syslog-ng              alertd              Script
    │                          │                    │                    │
    │ 1. log "TOTP_ENROLL_    │                    │                    │
    │    TRIGGER:username"    │                    │                    │
    ├─────────────────────────►│                    │                    │
    │                          │                    │                    │
    │                          │ 2. Write to        │                    │
    │                          │    /var/log/ltm    │                    │
    │                          ├───────────────────►│                    │
    │                          │                    │                    │
    │                          │                    │ 3. Pattern match   │
    │                          │                    │    TOTP_ENROLL_    │
    │                          │                    │    TRIGGER         │
    │                          │                    ├───────────────────►│
    │                          │                    │                    │
    │                          │                    │                    │ 4. Query API
    │                          │                    │                    │    for secret
    │                          │                    │                    ├────┐
    │                          │                    │                    │◄───┘
    │                          │                    │                    │
    │                          │                    │                    │ 5. tmsh modify
    │                          │                    │                    │    data-group
    │                          │                    │                    ├────┐
    │                          │                    │                    │◄───┘
    │                          │                    │                    │
```

### Create Script Directory

```bash
mkdir -p /config/totp
```

### Enrollment Script (totp_enroll.sh)

Create `/config/totp/totp_enroll.sh`:

```bash
#!/bin/bash
#
# totp_enroll.sh - Persist TOTP secret to data group on enrollment
#
# Triggered by: logger -p local0.alert "TOTP_ENROLL_TRIGGER:<username>"
# Reads username from log, queries API for secret, updates data group
#

LOGFILE="/var/log/ltm"
API_HOST="totp-api.mfa-demo.local"
API_PORT="443"
DG_NAME="totp_secrets_dg"

# Get API key from config data group
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

if [ -z "$API_KEY" ]; then
    logger -p local0.err "totp_enroll: Failed to retrieve API key from totp_config_dg"
    exit 1
fi

# Extract username from most recent trigger in log
USERNAME=$(grep "TOTP_ENROLL_TRIGGER:" "$LOGFILE" | tail -1 | sed 's/.*TOTP_ENROLL_TRIGGER://' | awk '{print $1}')

if [ -z "$USERNAME" ]; then
    logger -p local0.err "totp_enroll: No username found in trigger"
    exit 1
fi

# Query API for encrypted secret
RESPONSE=$(curl -sk -H "X-API-Key: $API_KEY" \
    "https://${API_HOST}:${API_PORT}/api/v1/export-secret?username=${USERNAME}" 2>/dev/null)

SECRET=$(echo "$RESPONSE" | grep -o '"secret":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SECRET" ]; then
    logger -p local0.err "totp_enroll: Failed to retrieve secret for user $USERNAME"
    exit 1
fi

# Update data group
tmsh modify ltm data-group internal "$DG_NAME" records add { "$USERNAME" { data "$SECRET" } } 2>/dev/null

if [ $? -eq 0 ]; then
    logger -p local0.info "totp_enroll: Committed secret for user $USERNAME to $DG_NAME"
else
    # Record may already exist, try modify
    tmsh modify ltm data-group internal "$DG_NAME" records modify { "$USERNAME" { data "$SECRET" } } 2>/dev/null
    if [ $? -eq 0 ]; then
        logger -p local0.info "totp_enroll: Updated secret for user $USERNAME in $DG_NAME"
    else
        logger -p local0.err "totp_enroll: Failed to commit secret for user $USERNAME"
        exit 1
    fi
fi

# Save configuration
tmsh save sys config partitions { Common } 2>/dev/null

exit 0
```

### Unenrollment Script (totp_unenroll.sh)

Create `/config/totp/totp_unenroll.sh`:

```bash
#!/bin/bash
#
# totp_unenroll.sh - Remove TOTP secret from data group on unenrollment
#
# Triggered by: logger -p local0.alert "TOTP_UNENROLL_TRIGGER:<username>"
#

LOGFILE="/var/log/ltm"
DG_NAME="totp_secrets_dg"

# Extract username from most recent trigger in log
USERNAME=$(grep "TOTP_UNENROLL_TRIGGER:" "$LOGFILE" | tail -1 | sed 's/.*TOTP_UNENROLL_TRIGGER://' | awk '{print $1}')

if [ -z "$USERNAME" ]; then
    logger -p local0.err "totp_unenroll: No username found in trigger"
    exit 1
fi

# Remove from data group
tmsh modify ltm data-group internal "$DG_NAME" records delete { "$USERNAME" } 2>/dev/null

if [ $? -eq 0 ]; then
    logger -p local0.info "totp_unenroll: Removed user $USERNAME from $DG_NAME"
else
    logger -p local0.warn "totp_unenroll: User $USERNAME not found in $DG_NAME (may already be removed)"
fi

# Save configuration
tmsh save sys config partitions { Common } 2>/dev/null

exit 0
```

### Set Script Permissions

```bash
chmod 700 /config/totp/totp_enroll.sh
chmod 700 /config/totp/totp_unenroll.sh
```

### Configure Alert Triggers

Append to `/config/user_alert.conf`:

```bash
cat >> /config/user_alert.conf << 'EOF'
alert TOTP_ENROLL_TRIGGER "TOTP_ENROLL_TRIGGER" {
    exec command="/config/totp/totp_enroll.sh"
}
alert TOTP_UNENROLL_TRIGGER "TOTP_UNENROLL_TRIGGER" {
    exec command="/config/totp/totp_unenroll.sh"
}
EOF
```

### Restart Alert Daemon

```bash
bigstart restart alertd
```

### Verify Alert Configuration

```bash
# Check alertd status
bigstart status alertd

# View alert configuration
cat /config/user_alert.conf | grep -A2 "TOTP_"
```

### Test Alert Mechanism

```bash
# Test enrollment trigger
logger -p local0.alert "TOTP_ENROLL_TRIGGER:testscript"
sleep 2
grep "totp_enroll" /var/log/ltm | tail -5

# Test unenrollment trigger
logger -p local0.alert "TOTP_UNENROLL_TRIGGER:testscript"
sleep 2
grep "totp_unenroll" /var/log/ltm | tail -5
```

---

## QR Code iFile

The QR code JavaScript library generates QR codes client-side for the enrollment page.

### Upload QR Code Library

```bash
# Copy qrcode.js to BIG-IP (from repo ifiles/ directory)
scp ifiles/qrcode.js admin@bigip.mfa-demo.local:/var/tmp/qrcode.js
```

### Create iFile Objects

```bash
# Create the file object
tmsh create sys file ifile qrcode_js source-path file:///var/tmp/qrcode.js

# Create the iFile reference
tmsh create ltm ifile qrcode_js file-name qrcode_js
```

### Verify iFile

```bash
# List iFiles
tmsh list ltm ifile qrcode_js

# Verify file content exists
tmsh list sys file ifile qrcode_js
```

---

## iRules

### irule_totp_shared

The shared iRule contains all common procedures used across the solution. This must be created first as other iRules depend on it.

**Key procedures:**

| Procedure | Purpose |
|-----------|---------|
| generate_secret | Creates random Base32 TOTP secret |
| generate_totp | Generates TOTP code from secret and time |
| verify_totp | Validates TOTP code with time skew |
| encrypt_secret | AES-256 encrypts secret for storage |
| decrypt_secret | Decrypts stored secret |
| bits_to_int | Binary to integer conversion (Tcl 8.5 compatible) |
| int_to_bits | Integer to binary conversion (Tcl 8.5 compatible) |

Create via GUI: **Local Traffic → iRules → iRule List → Create**

- Name: `irule_totp_shared`
- Definition: (paste content from `irules/irule_totp_shared.tcl`)

### irule_totp_enroll

The enrollment iRule handles the enrollment page generation, QR code display, and confirmation processing.

**Key events:**

| Event | Purpose |
|-------|---------|
| HTTP_REQUEST | Route enrollment requests |
| HTTP_RESPONSE | (unused) |

**Endpoints:**

| Path | Method | Purpose |
|------|--------|---------|
| /enroll | GET | Display enrollment page |
| /enroll | POST | Process enrollment confirmation |
| /reenroll | GET | Re-enrollment for existing users |
| /reenroll | POST | Process re-enrollment confirmation |

Create via GUI: **Local Traffic → iRules → iRule List → Create**

- Name: `irule_totp_enroll`
- Definition: (paste content from `irules/irule_totp_enroll.tcl`)

### Verify iRules

```bash
tmsh list ltm rule irule_totp_shared
tmsh list ltm rule irule_totp_enroll
```

---

## HTTP Profile

Create a dedicated HTTP profile for the enrollment virtual server:

```bash
tmsh create ltm profile http http_totp_enroll defaults-from http
```

---

## Virtual Server

### Create Enrollment Virtual Server

```bash
tmsh create ltm virtual vs_totp_enroll {
    destination 10.1.1.100:443
    ip-protocol tcp
    profiles replace-all-with {
        mfa-clientssl { context clientside }
        http_totp_enroll
        tcp
    }
    source-address-translation { type automap }
    rules { irule_totp_shared irule_totp_enroll }
}
```

### Verify Virtual Server

```bash
tmsh list ltm virtual vs_totp_enroll
```

Expected output:

```
ltm virtual vs_totp_enroll {
    destination 10.1.1.100:443
    ip-protocol tcp
    mask 255.255.255.255
    profiles {
        http_totp_enroll { }
        mfa-clientssl {
            context clientside
        }
        tcp { }
    }
    rules {
        irule_totp_shared
        irule_totp_enroll
    }
    source-address-translation {
        type automap
    }
    ...
}
```

---

## Access Policy

The enrollment access policy authenticates users before allowing TOTP enrollment.

### Create Access Profile

```bash
tmsh create apm profile access ap_totp_enroll {
    accept-languages add { en }
    default-language en
    type all
}
```

### Configure Access Policy (VPE)

1. Navigate to: **Access → Profiles / Policies → Access Profiles (Per-Session Policies)**

2. Click **ap_totp_enroll**, then **Edit Access Policy for Profile "ap_totp_enroll"**

3. Build the following policy flow:

```
┌─────────┐     ┌─────────────┐     ┌──────────────┐     ┌─────────┐
│  Start  │────►│ Logon Page  │────►│  Auth        │────►│ Allow   │
└─────────┘     └─────────────┘     │ (LocalDB/AD) │     └─────────┘
                                    └──────────────┘
                                           │
                                           │ Failure
                                           ▼
                                    ┌─────────┐
                                    │  Deny   │
                                    └─────────┘
```

### Step 1: Add Logon Page

1. Click the **+** after Start
2. Select **Logon Page** from the Logon tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | Enrollment Login |
| Field 1 (Username) | (default) |
| Field 2 (Password) | (default) |

4. Click **Save**

### Step 2: Add Authentication

**For Local DB:**

1. Click the **+** after Logon Page
2. Select **LocalDB Auth** from the Authentication tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | LocalDB Auth |
| AAA Server | /Common/mfa_users_db |

4. Click **Save**

**For Active Directory:**

1. Click the **+** after Logon Page
2. Select **AD Auth** from the Authentication tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | AD Auth |
| AAA Server | /Common/mfa_ad_aaa |

4. Click **Save**

### Step 3: Configure Endings

1. On the **Successful** branch, change ending to **Allow**
2. On the **Failure** branch, ensure ending is **Deny**

### Step 4: Apply Policy

1. Click **Apply Access Policy** (yellow banner at top)

### Attach Access Profile to Virtual Server

```bash
tmsh modify ltm virtual vs_totp_enroll profiles add { ap_totp_enroll }
```

### Verify Access Profile Attachment

```bash
tmsh list ltm virtual vs_totp_enroll profiles
```

---

## Rate Limiting

Enrollment rate limiting prevents abuse of the enrollment endpoint.

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| enroll_rate_max_attempts | 3 | Maximum enrollment attempts per user |
| enroll_rate_window_seconds | 600 | Window duration (10 minutes) |

### Rate Limit Behavior

- Users exceeding `enroll_rate_max_attempts` within `enroll_rate_window_seconds` are blocked
- Rate limits are tracked per username
- IP-based rate limiting is also applied
- Limits reset automatically after the window expires
- Administrators can reset limits via the Admin UI or API

### Modify Rate Limits

```bash
# Increase enrollment attempts allowed
tmsh modify ltm data-group internal totp_config_dg records modify {
    enroll_rate_max_attempts { data "5" }
}

# Extend lockout window to 1 hour
tmsh modify ltm data-group internal totp_config_dg records modify {
    enroll_rate_window_seconds { data "3600" }
}
```

---

## Testing Enrollment

### Prerequisites

- [ ] DNS resolution for totp-enroll.mfa-demo.local
- [ ] Test user exists in authentication backend
- [ ] Authenticator app installed on mobile device

### Test Procedure

1. **Access enrollment page:**
   ```
   https://totp-enroll.mfa-demo.local/enroll
   ```

2. **Log in with test credentials:**
   - Username: `testuser`
   - Password: `TestP@ss123!`

3. **View QR code:**
   - QR code should display with issuer name
   - Manual entry code should be visible

4. **Scan QR code:**
   - Open authenticator app
   - Scan QR code or enter manual code
   - Verify account appears with correct issuer

5. **Confirm enrollment:**
   - Enter 6-digit code from authenticator
   - Submit confirmation

6. **Verify success:**
   - Success message displayed
   - Check subtable for user entry:
     ```bash
     tmsh show ltm rule irule_totp_shared stats | grep -A5 "totp_users"
     ```

7. **Verify persistence:**
   - Wait for alert script execution (~2-5 seconds)
   - Check data group:
     ```bash
     tmsh list ltm data-group internal totp_secrets_dg records
     ```

### Test Re-Enrollment

1. **Access re-enrollment page:**
   ```
   https://totp-enroll.mfa-demo.local/reenroll
   ```

2. **Complete same flow as enrollment**

3. **Verify old authenticator no longer works:**
   - Previous codes should be rejected
   - Only new authenticator generates valid codes

---

## Troubleshooting

### QR Code Not Displaying

```bash
# Verify iFile exists
tmsh list ltm ifile qrcode_js

# Check browser console for JavaScript errors
# Verify iRule is returning correct Content-Type
```

### Authentication Failing

```bash
# Check access policy logs
tail -f /var/log/apm | grep ap_totp_enroll

# Verify AAA server configuration
tmsh list apm aaa local-db-instance mfa_users_db
```

### Enrollment Not Persisting

```bash
# Check alertd status
bigstart status alertd

# Verify alert configuration
grep "TOTP_ENROLL" /config/user_alert.conf

# Check for script errors
tail -f /var/log/ltm | grep totp_enroll

# Test API connectivity from script
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

### Rate Limited During Testing

```bash
# Reset enrollment rate limit via API
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-rate-reset?username=testuser"
```

### Encryption Key Issues

```bash
# Verify encryption key length (must be 32 characters)
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "encryption_key"

# Key should be exactly 32 characters
```

---

## Log Messages

Enrollment-related log patterns (see [Log Reference](appendicies/log-reference.md)):

| Pattern | Meaning |
|---------|---------|
| `TOTP_ENROLL_TRIGGER:<user>` | Enrollment trigger fired |
| `totp_enroll: Committed secret` | DG persistence successful |
| `TOTP_ENROLL_RATE:ATTEMPT` | Enrollment attempt logged |
| `TOTP_ENROLL_RATE:BLOCKED` | Enrollment rate limited |
| `TOTP_ENROLL_RATE:LOCKOUT` | Maximum attempts reached |

---

## Save Configuration

```bash
tmsh save sys config
```

---

## Configuration Summary

After completing this section, you should have:

| Component | Name/Value |
|-----------|------------|
| Config Data Group | totp_config_dg |
| Secrets Data Group | totp_secrets_dg |
| QR Code iFile | qrcode_js |
| Shared iRule | irule_totp_shared |
| Enrollment iRule | irule_totp_enroll |
| HTTP Profile | http_totp_enroll |
| Virtual Server | vs_totp_enroll (10.1.1.100:443) |
| Access Profile | ap_totp_enroll |
| Enrollment Script | /config/totp/totp_enroll.sh |
| Unenrollment Script | /config/totp/totp_unenroll.sh |

---

## Next Steps

Proceed to [06 - TOTP Verification API](06-totp-verification-api.md) to configure the verification API virtual servers used by the MFA portal for code validation.