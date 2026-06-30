# 10 - Administration

This section covers the Admin UI, API key management, user management, operational procedures, and routine maintenance tasks for the TOTP MFA solution.

---

## Admin UI Overview

The Admin UI provides a web-based interface for managing the TOTP MFA solution:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Admin UI Architecture                                │
└─────────────────────────────────────────────────────────────────────────────┘

     Administrator                 Admin UI VS                    Backend
           │                           │                             │
           │  1. Access Admin UI       │                             │
           ├──────────────────────────►│                             │
           │                           │                             │
           │  2. Dashboard             │                             │
           │◄──────────────────────────┤                             │
           │                           │                             │
           │  3. View Users            │  Query totp_users           │
           ├──────────────────────────►├────────────────────────────►│
           │                           │◄────────────────────────────┤
           │  4. User List             │                             │
           │◄──────────────────────────┤                             │
           │                           │                             │
           │  5. Reset Rate Limit      │  API call                   │
           ├──────────────────────────►├────────────────────────────►│
           │                           │◄────────────────────────────┤
           │  6. Confirmation          │                             │
           │◄──────────────────────────┤                             │
           │                           │                             │
```

### Admin UI Features

| Feature | Description |
|---------|-------------|
| Dashboard | Overview of enrolled users and system status |
| User List | View all enrolled TOTP users |
| User Details | View individual user enrollment status |
| Rate Limit Status | View current rate limit counters |
| Rate Limit Reset | Reset rate limits for individual users |
| Bulk Rate Reset | Clear all rate limits |
| User Unenroll | Remove user TOTP enrollment |
| User Delete | Delete user from subtable and data group |

---

## Admin UI Virtual Server

### Verify Admin UI Configuration

```bash
# Check virtual server
tmsh list ltm virtual vs_totp_admin

# Check iRules attached
tmsh list ltm virtual vs_totp_admin rules
```

### Admin UI Access

**URL:** `https://totp-admin.mfa-demo.local:443/`

**IP:** `https://10.1.1.104:443/`

> **Security Warning:** The Admin UI provides full access to TOTP management functions. Restrict access appropriately.

---

## Admin UI Security

### Option 1: Source IP Restriction

Restrict Admin UI access to specific IP addresses or networks:

```bash
# Create address list
tmsh create security firewall address-list admin_allowed_ips {
    addresses add { 10.10.10.0/24 192.168.1.100/32 }
}

# Create firewall rule
tmsh create security firewall rule-list admin_access_rules {
    rules add {
        allow_admin_ips {
            action accept
            source {
                address-lists add { admin_allowed_ips }
            }
        }
        deny_all {
            action drop
        }
    }
}

# Apply to virtual server
tmsh modify ltm virtual vs_totp_admin fw-enforced-policy admin_access_rules
```

**Alternative: Simple Source Address Filter**

```bash
# Modify VS to only accept from specific network
tmsh modify ltm virtual vs_totp_admin source 10.10.10.0/24
```

### Option 2: APM Authentication

Protect Admin UI with APM access policy requiring administrator credentials:

1. **Create Admin Access Profile:**

```bash
tmsh create apm profile access ap_totp_admin {
    accept-languages add { en }
    default-language en
    type all
}
```

2. **Configure VPE Policy:**
   - Logon Page (username/password)
   - LocalDB or AD Auth
   - Group check (require admin group membership)
   - Allow/Deny

3. **Attach to Virtual Server:**

```bash
tmsh modify ltm virtual vs_totp_admin profiles add { ap_totp_admin }
```

### Option 3: Client Certificate Authentication

Require client certificates for Admin UI access:

1. **Create server SSL profile with client auth:**

```bash
tmsh create ltm profile client-ssl mfa-clientssl-admin {
    defaults-from clientssl
    cert-key-chain add { mfa-ecc { cert mfa-ecc key mfa-ecc } }
    client-cert require
    ca-file admin-ca-bundle.crt
}
```

2. **Apply to Admin VS:**

```bash
tmsh modify ltm virtual vs_totp_admin profiles replace-all-with {
    mfa-clientssl-admin { context clientside }
    http_totp_admin
    tcp
}
```

---

## User Management

### View Enrolled Users

**Via Admin UI:**

1. Access `https://totp-admin.mfa-demo.local/`
2. Navigate to Users section
3. View enrolled user list

**Via API:**

```bash
# Get API key
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

# Check specific user enrollment
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"
```

**Via Data Group:**

```bash
# List all enrolled users
tmsh list ltm data-group internal totp_secrets_dg records | grep -E "^\s+\w+" | awk '{print $1}'

# Count enrolled users
tmsh list ltm data-group internal totp_secrets_dg records | grep -c "{"
```

### View User Details

**Via API:**

```bash
# Check enrollment status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"

# Check rate limit status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"

# Check enrollment rate status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-status?username=testuser"
```

### Unenroll User

Remove a user's TOTP enrollment (user will need to re-enroll):

**Via Admin UI:**

1. Navigate to user details
2. Click "Unenroll" button
3. Confirm action

**Via API:**

The unenroll process involves:

1. Removing from subtable
2. Triggering alert to remove from data group

```bash
# Trigger unenrollment (via log trigger)
logger -p local0.alert "TOTP_UNENROLL_TRIGGER:username"
```

**Via Direct Data Group Modification:**

```bash
# Remove from data group
tmsh modify ltm data-group internal totp_secrets_dg records delete { username }

# Save configuration
tmsh save sys config
```

> **Note:** Removing from data group does not immediately remove from subtable. The subtable entry will be used until TMM restart or manual clearing.

### Delete User Completely

Remove user from both subtable and data group:

**Via Admin UI:**

1. Navigate to user details
2. Click "Delete" button
3. Confirm action

**Via Manual Process:**

```bash
# Remove from data group
tmsh modify ltm data-group internal totp_secrets_dg records delete { username }

# Trigger subtable removal (via API or iRule)
# The Admin UI handles this automatically

# Save configuration
tmsh save sys config
```

### Bulk User Operations

**Export User List:**

```bash
# Export all enrolled usernames
tmsh list ltm data-group internal totp_secrets_dg records | \
    grep -E "^\s+\w+" | awk '{print $1}' > enrolled_users.txt
```

**Bulk Unenroll (Use with Caution):**

```bash
# Read users from file and unenroll
while read username; do
    logger -p local0.alert "TOTP_UNENROLL_TRIGGER:$username"
    sleep 1
done < users_to_unenroll.txt
```

---

## Rate Limit Management

### View Rate Limit Status

**Single User:**

```bash
# Verification rate status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"

# Enrollment rate status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-status?username=testuser"
```

**All Users:**

```bash
# Rate limit summary
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-summary"
```

### Reset Rate Limits

**Single User - Verification:**

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset?username=testuser"
```

**Single User - Enrollment:**

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-rate-reset?username=testuser"
```

**All Users - Verification Only:**

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-verify-all"
```

**All Users - Enrollment Only:**

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-enroll-all"
```

**All Users - All Rate Limits:**

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-all"
```

### Modify Rate Limit Configuration

**Adjust Verification Limits:**

```bash
# Increase max attempts
tmsh modify ltm data-group internal totp_config_dg records modify {
    rate_max_attempts { data "10" }
}

# Extend window duration (seconds)
tmsh modify ltm data-group internal totp_config_dg records modify {
    rate_window_seconds { data "600" }
}
```

**Adjust Enrollment Limits:**

```bash
# Increase max attempts
tmsh modify ltm data-group internal totp_config_dg records modify {
    enroll_rate_max_attempts { data "5" }
}

# Extend window duration (seconds)
tmsh modify ltm data-group internal totp_config_dg records modify {
    enroll_rate_window_seconds { data "1800" }
}
```

**Save Changes:**

```bash
tmsh save sys config
```

---

## API Key Management

### View Current API Key

```bash
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key"
```

### Rotate API Key

Regular API key rotation is a security best practice.

**Step 1: Generate New Key**

```bash
NEW_API_KEY=$(openssl rand -hex 32)
echo "New API Key: $NEW_API_KEY"
```

**Step 2: Update Data Group**

```bash
tmsh modify ltm data-group internal totp_config_dg records modify {
    api_key { data "$NEW_API_KEY" }
}
tmsh save sys config
```

**Step 3: Update Alert Scripts**

If alert scripts use hardcoded API keys (not recommended), update them:

```bash
# Edit scripts on both HA units
vi /config/totp/totp_enroll.sh
vi /config/totp/totp_unenroll.sh
```

> **Note:** The provided alert scripts retrieve the API key dynamically from the data group, so no script updates are needed.

**Step 4: Update External Integrations**

Update any external applications or scripts that use the API key.

**Step 5: Sync Configuration (HA)**

```bash
tmsh run cm config-sync to-group mfa-sync-failover-dg
```

**Step 6: Verify New Key Works**

```bash
curl -sk -H "X-API-Key: $NEW_API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

### API Key Security Best Practices

| Practice | Description |
|----------|-------------|
| Regular rotation | Rotate quarterly or after personnel changes |
| Secure storage | Store in vault or secrets manager |
| Minimal exposure | Only share with systems that need it |
| Audit access | Log and monitor API usage |
| Unique keys | Use different keys for different environments |

---

## Encryption Key Management

### View Current Encryption Key

```bash
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "encryption_key"
```

> **Warning:** The encryption key protects all stored TOTP secrets. Handle with extreme care.

### Backup Encryption Key

**Critical:** Always maintain secure backups of the encryption key.

```bash
# Extract and save securely
ENC_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "encryption_key" | grep "data" | awk '{print $2}' | tr -d '"')
echo "Encryption Key: $ENC_KEY"

# Store in secure vault (not in plaintext files!)
```

### Encryption Key Rotation

Rotating the encryption key requires re-encrypting all secrets:

> **Warning:** This is a complex operation. Plan carefully and test in non-production first.

**Process Overview:**

1. Export all current secrets (decrypted)
2. Generate new encryption key
3. Re-encrypt all secrets with new key
4. Update data group with new encrypted secrets
5. Update encryption key in config
6. Clear subtable to force reload

**This process is not covered in detail as it requires custom scripting and careful planning.**

### Encryption Key Recovery

If the encryption key is lost:

1. **All existing secrets are unrecoverable**
2. Generate new encryption key
3. Clear secrets data group:
   ```bash
   tmsh modify ltm data-group internal totp_secrets_dg records none
   ```
4. Update config with new key
5. **All users must re-enroll**

---

## Configuration Management

### View Current Configuration

```bash
# View all TOTP configuration
tmsh list ltm data-group internal totp_config_dg records
```

### Modify Configuration Parameters

**Change Issuer Name:**

```bash
tmsh modify ltm data-group internal totp_config_dg records modify {
    issuer { data "New Issuer Name" }
}
```

**Change TOTP Parameters:**

```bash
# Code length (6 or 8 digits)
tmsh modify ltm data-group internal totp_config_dg records modify {
    code_length { data "6" }
}

# Time step (typically 30 seconds)
tmsh modify ltm data-group internal totp_config_dg records modify {
    time_step { data "30" }
}

# Time skew allowance (number of intervals)
tmsh modify ltm data-group internal totp_config_dg records modify {
    time_skew { data "1" }
}
```

**Enable/Disable Encryption:**

```bash
# Disable encryption (NOT RECOMMENDED)
tmsh modify ltm data-group internal totp_config_dg records modify {
    encrypt_secrets { data "0" }
}

# Enable encryption
tmsh modify ltm data-group internal totp_config_dg records modify {
    encrypt_secrets { data "1" }
}
```

**Save Changes:**

```bash
tmsh save sys config
```

### Configuration Backup

**Export Data Groups:**

```bash
# Export to file
tmsh list ltm data-group internal totp_config_dg > /var/tmp/totp_config_backup.txt
tmsh list ltm data-group internal totp_secrets_dg > /var/tmp/totp_secrets_backup.txt

# Copy off-system
scp /var/tmp/totp_*_backup.txt admin@backup-server:/backups/
```

**Full UCS Backup:**

```bash
tmsh save sys ucs /var/local/ucs/totp-mfa-$(date +%Y%m%d).ucs
```

---

## Monitoring and Logging

### Health Monitoring

**API Health Check:**

```bash
# Quick health check
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

**Create Health Monitor (Optional):**

```bash
tmsh create ltm monitor http totp_api_health {
    defaults-from http
    send "GET /api/v1/health HTTP/1.1\r\nHost: totp-api.mfa-demo.local\r\nX-API-Key: YOUR_API_KEY\r\nConnection: close\r\n\r\n"
    recv "\"status\":\"ok\""
    interval 30
    timeout 91
}
```

### Log Monitoring

**Watch TOTP Events:**

```bash
tail -f /var/log/ltm | grep -iE "totp|mfa"
```

**Watch Enrollment Events:**

```bash
tail -f /var/log/ltm | grep -E "TOTP_ENROLL|totp_enroll"
```

**Watch Rate Limit Events:**

```bash
tail -f /var/log/ltm | grep -E "TOTP_RATE|TOTP_ENROLL_RATE"
```

**Watch Authentication Events:**

```bash
tail -f /var/log/apm | grep -E "ap_mfa_portal|ap_totp_enroll"
```

### Log Analysis

**Count Enrollments (Last 24 Hours):**

```bash
grep "totp_enroll: Committed" /var/log/ltm | \
    awk -v d="$(date -d '24 hours ago' '+%b %d')" '$1" "$2 >= d' | wc -l
```

**Count Failed Verifications:**

```bash
grep "TOTP_RATE:BLOCKED" /var/log/ltm | wc -l
```

**Find Rate-Limited Users:**

```bash
grep "TOTP_RATE:LOCKOUT" /var/log/ltm | \
    sed 's/.*LOCKOUT://' | awk '{print $1}' | sort | uniq -c | sort -rn
```

### SNMP Monitoring (Optional)

Configure SNMP traps for TOTP events:

```bash
# Create alert for TOTP lockouts
cat >> /config/user_alert.conf << 'EOF'
alert TOTP_LOCKOUT_SNMP "TOTP_RATE:LOCKOUT" {
    snmptrap OID=".1.3.6.1.4.1.3375.2.4.0.500"
}
EOF

bigstart restart alertd
```

---

## Routine Maintenance Tasks

### Daily Tasks

| Task | Command/Action |
|------|----------------|
| Check API health | `curl -sk -H "X-API-Key: $API_KEY" https://totp-api.mfa-demo.local/api/v1/health` |
| Review logs for errors | `grep -i error /var/log/ltm \| tail -50` |
| Check sync status (HA) | `tmsh show cm sync-status` |

### Weekly Tasks

| Task | Command/Action |
|------|----------------|
| Review enrolled user count | `tmsh list ltm data-group internal totp_secrets_dg records \| grep -c "{"` |
| Review rate limit summary | `curl -sk -H "X-API-Key: $API_KEY" https://totp-api.mfa-demo.local/api/v1/rate-summary` |
| Check NTP sync | `ntpq -p` |
| Review authentication failures | `grep -c "TOTP_RATE:BLOCKED" /var/log/ltm` |

### Monthly Tasks

| Task | Command/Action |
|------|----------------|
| Configuration backup | `tmsh save sys ucs /var/local/ucs/totp-mfa-$(date +%Y%m%d).ucs` |
| Review access logs | Audit APM session logs |
| Test failover (HA) | `tmsh run sys failover standby` on active |
| Verify alert scripts | `logger -p local0.alert "TOTP_ENROLL_TRIGGER:test"` |

### Quarterly Tasks

| Task | Command/Action |
|------|----------------|
| Rotate API key | See API Key Rotation section |
| Review rate limit settings | Adjust based on usage patterns |
| Test disaster recovery | Full restore test |
| Security review | Audit admin access, review logs |
| Certificate renewal check | `tmsh show sys crypto cert mfa-ecc` |

### Annual Tasks

| Task | Command/Action |
|------|----------------|
| Certificate renewal | Generate new certificates before expiration |
| Full documentation review | Update procedures as needed |
| Capacity planning review | Evaluate user growth, plan scaling |
| Security audit | Full security assessment |

---

## Troubleshooting Common Issues

### Admin UI Not Loading

```bash
# Check VS status
tmsh show ltm virtual vs_totp_admin

# Check iRule errors
tail -f /var/log/ltm | grep -i error

# Verify iRules attached
tmsh list ltm virtual vs_totp_admin rules
```

### API Not Responding

```bash
# Check both API virtual servers
tmsh show ltm virtual vs_totp_api
tmsh show ltm virtual vs_totp_api_internal

# Test internal endpoint
curl -s "http://10.255.255.255:80/api/v1/health"

# Check for iRule errors
tail -f /var/log/ltm | grep -iE "error|totp"
```

### Users Cannot Enroll

```bash
# Check enrollment VS
tmsh show ltm virtual vs_totp_enroll

# Check access policy
tmsh list apm profile access ap_totp_enroll

# Check alert system
bigstart status alertd
grep "TOTP_ENROLL" /var/log/ltm | tail -10
```

### Users Cannot Authenticate

```bash
# Check MFA portal VS
tmsh show ltm virtual vs_mfa_portal

# Check HTTP AAA
tmsh list apm aaa http http_aaa_totp_verify

# Test API verification
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local/api/v1/verify?username=testuser&code=123456"

# Check NTP
ntpq -p
```

### Data Group Not Updating

```bash
# Check alert scripts
ls -la /config/totp/

# Check alertd
bigstart status alertd

# Test trigger manually
logger -p local0.alert "TOTP_ENROLL_TRIGGER:debuguser"
sleep 3
grep "totp_enroll" /var/log/ltm | tail -5

# Check API connectivity from script
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local/api/v1/health"
```

---

## Administrative Scripts

### User Enrollment Report

Create a script to generate enrollment reports:

```bash
#!/bin/bash
# /config/totp/enrollment_report.sh

echo "=== TOTP Enrollment Report ===" 
echo "Generated: $(date)"
echo ""

# Count enrolled users
ENROLLED=$(tmsh list ltm data-group internal totp_secrets_dg records | grep -c "{")
echo "Total Enrolled Users: $ENROLLED"
echo ""

# List users
echo "Enrolled Users:"
tmsh list ltm data-group internal totp_secrets_dg records | \
    grep -E "^\s+\w+" | awk '{print "  - " $1}'
```

### Rate Limit Report

```bash
#!/bin/bash
# /config/totp/ratelimit_report.sh

API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

echo "=== Rate Limit Report ==="
echo "Generated: $(date)"
echo ""

curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-summary" | python -m json.tool
```

### Health Check Script

```bash
#!/bin/bash
# /config/totp/health_check.sh

API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

echo "=== TOTP Health Check ==="
echo "Time: $(date)"
echo ""

# API Health
echo -n "API Health: "
HEALTH=$(curl -sk -H "X-API-Key: $API_KEY" "https://totp-api.mfa-demo.local:443/api/v1/health" 2>/dev/null)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "OK"
else
    echo "FAILED"
fi

# Internal API
echo -n "Internal API: "
INTERNAL=$(curl -s "http://10.255.255.255:80/api/v1/health" 2>/dev/null)
if echo "$INTERNAL" | grep -q '"status":"ok"'; then
    echo "OK"
else
    echo "FAILED"
fi

# Alert Daemon
echo -n "Alert Daemon: "
if bigstart status alertd | grep -q "run"; then
    echo "OK"
else
    echo "FAILED"
fi

# NTP Sync
echo -n "NTP Sync: "
if ntpq -p 2>/dev/null | grep -q "^\*"; then
    echo "OK"
else
    echo "WARNING - Check NTP"
fi

# Enrolled Users
ENROLLED=$(tmsh list ltm data-group internal totp_secrets_dg records 2>/dev/null | grep -c "{")
echo "Enrolled Users: $ENROLLED"

echo ""
echo "=== End Health Check ==="
```

---

## Save Configuration

```bash
tmsh save sys config
```

---

## Configuration Summary

### Admin UI

| Component | Value |
|-----------|-------|
| Virtual Server | vs_totp_admin |
| IP:Port | 10.1.1.104:443 |
| FQDN | totp-admin.mfa-demo.local |
| iRule | irule_totp_admin_ui |

### Key Management

| Key | Location | Rotation |
|-----|----------|----------|
| API Key | totp_config_dg → api_key | Quarterly |
| Encryption Key | totp_config_dg → encryption_key | Rarely (complex) |

### Maintenance Schedule

| Frequency | Tasks |
|-----------|-------|
| Daily | Health check, log review |
| Weekly | User count, rate limits, NTP |
| Monthly | Backup, failover test |
| Quarterly | API key rotation, security review |
| Annual | Certificate renewal, capacity planning |

---

## Next Steps

Proceed to [11 - Testing](11-testing.md) for comprehensive testing procedures, test matrices, and validation scripts.