# Quick-Start Checklist — Minimal Single-Unit Deployment

This checklist provides the fastest path to a working MFA deployment on a single BIG-IP unit. For detailed explanations, refer to the corresponding documentation section. For all configurable values, see the Configuration Values Reference.

> **Prerequisites:** BIG-IP TMOS 17.5.1.5 with APM + LTM provisioned, NTP synchronized, DNS configured.

---

## Service Endpoints Reference

| Service | FQDN | IP:Port | Purpose |
|---------|------|---------|---------|
| MFA Portal | portal.mfa-demo.local | 10.1.1.102:443 | User login with MFA |
| TOTP Enrollment | totp-enroll.mfa-demo.local | 10.1.1.100:443 | Initial TOTP enrollment |
| TOTP API (External) | totp-api.mfa-demo.local | 10.1.1.101:443 | External API access |
| TOTP API (Internal) | — | 10.255.255.255:80 | HTTP Auth agent calls |
| Admin UI | totp-admin.mfa-demo.local | 10.1.1.104:443 | Administration interface |

---

## Phase 1 — Foundation

### 1.1 Verify Provisioning
```bash
tmsh show sys provision | grep -E "ltm|apm"
```
Both must show `nominal`.

### 1.2 Configure NTP
```bash
tmsh modify sys ntp servers replace-all-with { 0.pool.ntp.org 1.pool.ntp.org }
tmsh save sys config
```
Verify: `ntpq -p` — look for `*` indicating sync.

### 1.3 Create VLANs and Self-IPs
```bash
# External VLAN for user-facing services
tmsh create net vlan external interfaces replace-all-with { 1.1 }
tmsh create net self external-self address 10.1.1.1/24 vlan external allow-service default

# Internal VLAN for non-routable API (optional but recommended)
tmsh create net vlan internal interfaces replace-all-with { 1.2 }
tmsh create net self internal-self address 10.255.255.254/24 vlan internal allow-service default

# Default route
tmsh create net route default-route gw 10.1.1.254 network default
tmsh save sys config
```

### 1.4 Create SSL Certificate

**Option A — ECC (Recommended):**
```bash
tmsh create sys crypto key mfa-ecc key-type ec-private curve-name secp384r1 gen-certificate \
    country "CA" common-name "*.mfa-demo.local" organization "MFA Demo" \
    subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

**Option B — RSA (Legacy Compatibility):**
```bash
tmsh create sys crypto key mfa-rsa key-size 2048 gen-certificate \
    country "CA" common-name "*.mfa-demo.local" organization "MFA Demo" \
    subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

### 1.5 Create SSL Profiles

**For ECC certificate:**
```bash
tmsh create ltm profile client-ssl mfa-clientssl defaults-from clientssl \
    cert-key-chain add { mfa-ecc { cert mfa-ecc key mfa-ecc } }
```

**For RSA certificate:**
```bash
tmsh create ltm profile client-ssl mfa-clientssl defaults-from clientssl \
    cert mfa-rsa key mfa-rsa
```

**Server SSL (for alert script API calls):**
```bash
tmsh create ltm profile server-ssl mfa-serverssl defaults-from serverssl-insecure-compatible
```

---

## Phase 2 — User Database

### 2.1 Create Authentication Backend

**Option A — Local DB (Lab/Testing):**
```bash
tmsh create apm aaa local-db-instance mfa_users_db lockout-threshold 5 auto-unlock-interval 300
```

**Option B — Active Directory (Production):**

Configure via GUI: Access → Authentication → Active Directory → Create

| Field | Value |
|-------|-------|
| Name | mfa_ad_aaa |
| Domain Name | corp.example.com |
| Server Connection | Direct |
| Domain Controller | dc01.corp.example.com |
| Admin Name | svc_bigip@corp.example.com |
| Admin Password | (service account password) |

### 2.2 Add Test Users (Local DB Only)

**Single user:**
```bash
ldbutil --add --uname="testuser" --password="TestP@ss123!" \
    --first_name="Test" --last_name="User" --email="testuser@mfa-demo.local" \
    --user_groups="mfaUsers" --change_passwd="0" \
    --login_failures="0" --locked_out="0" --instance="/Common/mfa_users_db"
```

**Additional test users:**
```bash
ldbutil --add --uname="admin1" --password="AdminP@ss123!" \
    --first_name="Admin" --last_name="One" --email="admin1@mfa-demo.local" \
    --user_groups="mfaAdmins" --change_passwd="0" \
    --login_failures="0" --locked_out="0" --instance="/Common/mfa_users_db"

ldbutil --add --uname="user2" --password="UserP@ss123!" \
    --first_name="Regular" --last_name="User" --email="user2@mfa-demo.local" \
    --user_groups="mfaUsers" --change_passwd="0" \
    --login_failures="0" --locked_out="0" --instance="/Common/mfa_users_db"
```

### 2.3 Verify Local DB Users
```bash
ldbutil --list --instance="/Common/mfa_users_db"
```

---

## Phase 3 — TOTP Infrastructure

### 3.1 Generate Secure Keys
```bash
# Generate 32-character encryption key (AES-256)
TOTP_ENC_KEY=$(openssl rand -base64 32 | tr -d '\n' | cut -c1-32)

# Generate API key (64 hex characters)
TOTP_API_KEY=$(openssl rand -hex 32)

echo "Encryption Key: $TOTP_ENC_KEY"
echo "API Key: $TOTP_API_KEY"
```

> **Important:** Save both values securely. The encryption key protects stored secrets.

### 3.2 Create Data Groups
```bash
# Secrets storage (starts empty)
tmsh create ltm data-group internal totp_secrets_dg type string

# Configuration data group
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

tmsh save sys config
```

### 3.3 Deploy Alert Scripts
```bash
# Create directory
mkdir -p /config/totp

# Copy scripts (from repo)
cp scripts/totp_enroll.sh /config/totp/totp_enroll.sh
cp scripts/totp_unenroll.sh /config/totp/totp_unenroll.sh

# Set permissions
chmod 700 /config/totp/*.sh

# Configure alert triggers
cat >> /config/user_alert.conf << 'EOF'
alert TOTP_ENROLL_TRIGGER "TOTP_ENROLL_TRIGGER" {
    exec command="/config/totp/totp_enroll.sh"
}
alert TOTP_UNENROLL_TRIGGER "TOTP_UNENROLL_TRIGGER" {
    exec command="/config/totp/totp_unenroll.sh"
}
EOF

# Restart alertd
bigstart restart alertd
```

### 3.4 Verify Alert Scripts
```bash
# Test enrollment trigger
logger -p local0.alert "TOTP_ENROLL_TRIGGER:alerttest"
sleep 2
grep "totp_enroll" /var/log/ltm | tail -3

# Test unenrollment trigger
logger -p local0.alert "TOTP_UNENROLL_TRIGGER:alerttest"
sleep 2
grep "totp_unenroll" /var/log/ltm | tail -3
```

---

## Phase 4 — iRules and iFile

### 4.1 Upload QR Code Library
```bash
# Copy qrcode.js to BIG-IP
scp ifiles/qrcode.js root@bigip.mfa-demo.local:/var/tmp/qrcode.js

# Create iFile
tmsh create sys file ifile qrcode_js source-path file:///var/tmp/qrcode.js
tmsh create ltm ifile qrcode_js file-name qrcode_js
```

### 4.2 Create iRules

Create iRules via GUI (Local Traffic → iRules → iRule List → Create) in this exact order:

| Order | iRule Name | Source File |
|-------|------------|-------------|
| 1 | irule_totp_shared | irules/irule_totp_shared.tcl |
| 2 | irule_totp_enroll | irules/irule_totp_enroll.tcl |
| 3 | irule_totp_api | irules/irule_totp_api.tcl |
| 4 | irule_idp_mfa | irules/irule_idp_mfa.tcl |
| 5 | irule_totp_admin_ui | irules/irule_totp_admin_ui.tcl |

> **Note:** `irule_totp_shared` must be created first as other iRules depend on its procedures.

---

## Phase 5 — Virtual Servers

### 5.1 Create HTTP Profiles
```bash
tmsh create ltm profile http http_totp_enroll defaults-from http
tmsh create ltm profile http http_totp_api defaults-from http
tmsh create ltm profile http http_mfa_portal defaults-from http
tmsh create ltm profile http http_totp_admin defaults-from http
```

### 5.2 Create TOTP Enrollment VS
```bash
tmsh create ltm virtual vs_totp_enroll \
    destination 10.1.1.100:443 \
    ip-protocol tcp \
    profiles replace-all-with { mfa-clientssl { context clientside } http_totp_enroll tcp } \
    source-address-translation { type automap } \
    rules { irule_totp_shared irule_totp_enroll }
```

### 5.3 Create TOTP API VS (External)
```bash
tmsh create ltm virtual vs_totp_api \
    destination 10.1.1.101:443 \
    ip-protocol tcp \
    profiles replace-all-with { mfa-clientssl { context clientside } http_totp_api tcp } \
    source-address-translation { type automap } \
    rules { irule_totp_shared irule_totp_api }
```

### 5.4 Create TOTP API VS (Internal — Non-Routable)
```bash
tmsh create ltm virtual vs_totp_api_internal \
    destination 10.255.255.255:80 \
    ip-protocol tcp \
    profiles replace-all-with { http_totp_api tcp } \
    source-address-translation { type automap } \
    rules { irule_totp_shared irule_totp_api }
```

### 5.5 Create MFA Portal VS
```bash
tmsh create ltm virtual vs_mfa_portal \
    destination 10.1.1.102:443 \
    ip-protocol tcp \
    profiles replace-all-with { mfa-clientssl { context clientside } http_mfa_portal tcp } \
    source-address-translation { type automap } \
    rules { irule_totp_shared irule_idp_mfa }
```

### 5.6 Create Admin UI VS
```bash
tmsh create ltm virtual vs_totp_admin \
    destination 10.1.1.104:443 \
    ip-protocol tcp \
    profiles replace-all-with { mfa-clientssl { context clientside } http_totp_admin tcp } \
    source-address-translation { type automap } \
    rules { irule_totp_shared irule_totp_admin_ui }
```

### 5.7 Save Configuration
```bash
tmsh save sys config
```

---

## Phase 6 — Access Policies

### 6.1 Create HTTP AAA Object (GUI Only)

Navigate to: Access → Authentication → HTTP → Create

| Field | Value |
|-------|-------|
| Name | http_aaa_totp_verify |
| Authentication Type | Custom Post |
| Start URI | http://10.255.255.255:80 |
| Form Action | /api/v1/verify |
| Form Parameter For User Name | username |
| Form Parameter For Password | code |
| Custom Post Body | username=%{session.logon.last.username}&code=%{session.logon.last.totp_code} |
| Successful Logon Detection Match Type | By Specific String in Response |
| Successful Logon Detection Match Value | "success":true |

### 6.2 Create Enrollment Access Profile

```bash
tmsh create apm profile access ap_totp_enroll \
    accept-languages add { en } \
    default-language en \
    type all
```

**VPE Policy Flow:**
1. Start → Logon Page (username only)
2. Logon Page → LocalDB Auth (or AD Auth)
3. Auth Success → Allow
4. Auth Failure → Deny

Attach to VS:
```bash
tmsh modify ltm virtual vs_totp_enroll profiles add { ap_totp_enroll }
```

### 6.3 Create MFA Portal Access Profile

```bash
tmsh create apm profile access ap_mfa_portal \
    accept-languages add { en } \
    default-language en \
    type all
```

**VPE Policy Flow:**
1. Start → Logon Page (username + password)
2. Logon Page → LocalDB Auth (or AD Auth)
3. Auth Success → Enrollment Check Macro
4. **If Not Enrolled** → Redirect-Enroll Ending (purple, type=Redirect, URL=https://totp-enroll.mfa-demo.local:443/enroll)
5. **If Enrolled** → TOTP Logon Page (collect `session.logon.last.totp_code`)
6. TOTP Logon Page → HTTP Auth (http_aaa_totp_verify)
7. HTTP Auth Success → Allow + Webtop
8. HTTP Auth Failure → Deny

**Create Webtop Resources:**
```bash
# Full webtop
tmsh create apm profile webtop webtop_mfa type full

# Reset Authenticator link
tmsh create apm resource webtop-link link_reset_authenticator \
    application-uri "https://totp-enroll.mfa-demo.local:443/reenroll" \
    caption "Reset Authenticator"

# Admin UI link (optional)
tmsh create apm resource webtop-link link_totp_admin \
    application-uri "https://totp-admin.mfa-demo.local:443/" \
    caption "TOTP Admin"
```

Attach to VS:
```bash
tmsh modify ltm virtual vs_mfa_portal profiles add { ap_mfa_portal }
tmsh save sys config
```

---

## Phase 7 — DNS and Testing

### 7.1 Configure DNS

**Option A — Local hosts file (testing):**
```bash
cat >> /etc/hosts << 'EOF'
10.1.1.100  totp-enroll.mfa-demo.local
10.1.1.101  totp-api.mfa-demo.local
10.1.1.102  portal.mfa-demo.local
10.1.1.104  totp-admin.mfa-demo.local
EOF
```

**Option B — DNS Server (production):**
Add A records for each FQDN pointing to the corresponding IP.

### 7.2 Verify API Health
```bash
# Get API key from config
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}')

# Test internal endpoint
curl -s -H "X-API-Key: $API_KEY" http://10.255.255.255:80/api/v1/health
```
Expected: `{"status":"ok"}`

### 7.3 Test Enrollment Flow

1. Browse to `https://portal.mfa-demo.local`
2. Log in with test credentials (`testuser` / `TestP@ss123!`)
3. Should redirect to enrollment page
4. Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
5. Enter 6-digit code to confirm enrollment
6. Should redirect back to portal

### 7.4 Test MFA Login

1. Browse to `https://portal.mfa-demo.local`
2. Log in with credentials
3. Enter TOTP code from authenticator app
4. Should reach webtop with "Reset Authenticator" and "TOTP Admin" links

### 7.5 Test Admin UI

1. Browse to `https://totp-admin.mfa-demo.local`
2. Verify dashboard shows enrolled user
3. Test viewing user details
4. Test rate limit reset function

### 7.6 Test Re-Enrollment

1. From webtop, click "Reset Authenticator"
2. Scan new QR code
3. Confirm with new code
4. Old authenticator should no longer work

---

## Phase 8 — Save and Verify

### 8.1 Final Configuration Save
```bash
tmsh save sys config
```

### 8.2 Verify All Components
```bash
# List virtual servers
tmsh list ltm virtual one-line | grep -E "vs_totp|vs_mfa"

# List iRules
tmsh list ltm rule one-line | grep totp

# List data groups
tmsh list ltm data-group internal one-line | grep totp

# Check access profiles
tmsh list apm profile access one-line | grep -E "ap_totp|ap_mfa"
```

---

## Post-Deployment Checklist

- [ ] **Security:** Restrict Admin UI access via APM profile or source IP filter
- [ ] **Backup:** Export and securely store encryption key from `totp_config_dg`
- [ ] **HA:** Configure config-sync if using HA pair (see Appendix B)
- [ ] **Monitoring:** Set up alerts for failed authentications
- [ ] **Documentation:** Record all customized values for disaster recovery

---

## Troubleshooting Quick Reference

| Issue | Check |
|-------|-------|
| QR code not displaying | Verify iFile created correctly, check browser console for JS errors |
| TOTP code rejected | Check NTP sync (`ntpq -p`), verify `time_skew` setting in config |
| "Rate limited" error | Wait for `rate_window_seconds`, or reset via Admin UI |
| Enrollment not persisting | Check `alertd` running (`bigstart status alertd`), verify `user_alert.conf` |
| HTTP Auth failing | Verify internal VS reachable, check form body syntax in HTTP AAA |
| Redirect loop after enrollment | Verify enrollment macro correctly queries API, check session variables |
| Admin UI not loading | Verify `irule_totp_admin_ui` attached to VS, check for Tcl errors in `/var/log/ltm` |

---

## Next Steps

- Review [01-overview.md](01-overview.md) for architecture details
- Configure AD integration: [appendix-a-ad-integration.md](appendix-a-ad-integration.md)
- Set up HA sync: [appendix-b-ha-sync.md](appendix-b-ha-sync.md)
- See all configurable values: [appendix-c-config-values.md](appendix-c-config-values.md)

