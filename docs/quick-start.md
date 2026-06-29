# Quick-Start Checklist --- Minimal Single-Unit Deployment
This checklist provides the fastest path to a working MFA deployment on a single BIG-IP unit. For a full explanation of each step, refer to the corresponding documentation section. For all values that need customization, refer to the Configuration Values Reference.
> Prerequisites: BIG-IP TMOS 17.5.1.5 with APM + LTM provisioned, NTP synchronized, DNS configured.
## Phase 1 --- Foundation
- [ ] **1. Verify provisioning**
```bash
tmsh show sys provision | grep -E "ltm|apm"
```
Both must show nominal.
- [ ] **2. Configure NTP**
```bash
tmsh modify sys ntp servers replace-all-with { 0.pool.ntp.org 1.pool.ntp.org }
tmsh save sys config
```
Verify: ntpq -p --- look for * indicating sync.
- [ ] **3. Create VLANs and self-IPs**
```bash
tmsh create net vlan external interfaces replace-all-with { 1.1 }
tmsh create net self external-self address 10.1.1.1/24 vlan external allow-service default
tmsh create net route default-route gw 10.1.1.254 network default
tmsh save sys config
```
- [ ] **4. Create SSL certificate (ECC recommended)**
```bash
tmsh create sys crypto key mfa-ecc key-type ec-private curve-name secp384r1 gen-certificate 
    country "CA" common-name ".mfa-demo.local" organization "MFA Demo" 
    subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local"
```
- [ ] **5. Create SSL profiles**
```bash
tmsh create ltm profile client-ssl mfa-clientssl defaults-from clientssl 
    cert-key-chain add { mfa-ecc { cert mfa-ecc key mfa-ecc } }
tmsh create ltm profile server-ssl mfa-serverssl defaults-from serverssl-insecure-compatible
```
## Phase 2 --- User Database
- [ ] **6. Create local DB instance (Option A) or configure AD AAA (Option B)**
Option A --- Local DB:
```bash
tmsh create apm aaa localdb mfa_users_db lockout-threshold 5 auto-unlock-interval 300
```
Option B --- Active Directory:
Configure via GUI: Access then Authentication then Active Directory then Create
- [ ] **7. Add test users (Option A only)**
```bash
ldbutil --add --uname="testuser" --password="TestP@ss~" 
    --first_name="Test" --last_name="User" --email="test@mfa-demo.local" 
    --user_groups="mfaUsers" --change_passwd="1" 
    --login_failures="0" --locked_out="0" --instance="/Common/mfa_users_db"
```
## Phase 3 --- TOTP Infrastructure
- [ ] **8. Generate keys**
```bash
TOTP_ENC_KEY=(opensslrand−base6432);
TOTP_A​PI_K​EY=(openssl rand -hex 32);
echo "Encryption Key: $TOTP_ENC_KEY";
echo "API Key: $TOTP_API_KEY"
```
Save both values securely.
- [ ] **9. Create data groups**
```bash
tmsh create ltm data-group internal totp_secrets_dg type string
tmsh create ltm data-group internal totp_config_dg type string
tmsh modify ltm data-group internal totp_config_dg records replace-all-with { 
    encryption_key { data "$TOTP_ENC_KEY" } 
    issuer { data "mfa-demo" } 
    api_key { data "$TOTP_API_KEY" } 
    rate_max_attempts { data "5" } 
    rate_window_seconds { data "300" } 
    enroll_rate_max_attempts { data "3" } 
    enroll_rate_window_seconds { data "600" } 
}
tmsh save sys config
```
- [ ] **10. Deploy alert scripts**
```bash
mkdir -p /config/totp
scp scripts/totp_enroll.sh scripts/totp_unenroll.sh root@BIGIP-IP:/config/totp/
ssh root@BIGIP-IP "chmod 700 /config/totp/.sh"
cat scripts/user_alert.conf >> /config/user_alert.conf
```
- [ ] **11. Test alert mechanism**
```bash
logger -p local0.alert "TOTP_ENROLL_TRIGGER:alerttest"
sleep 2
grep "totp-enroll" /var/log/ltm | tail -3
```
## Phase 4 --- iRules and iFile
- [ ] **12. Create QR code iFile**
```bash
tmsh create sys file ifile qrcode_js source-path file:///var/tmp/qrcode.js
tmsh create ltm ifile qrcode_js file-name qrcode_js
```
- [ ] **13. Create iRules via GUI (Local Traffic then iRules then Create) in this order:**

     irule_totp_shared --- from irules/irule_totp_shared.tcl
     irule_totp_enroll --- from irules/irule_totp_enroll.tcl
     irule_totp_api --- from irules/irule_totp_api.tcl
     irule_idp_mfa --- from irules/irule_idp_mfa.tcl
     irule_totp_admin_ui --- from irules/irule_totp_admin_ui.tcl
## Phase 5 --- Virtual Servers
- [ ] **14. Create HTTP profiles**
```bash
    tmsh create ltm profile http http_totp_enroll defaults-from http
    tmsh create ltm profile http http_totp_api defaults-from http
    tmsh create ltm profile http http_mfa_portal defaults-from http
    tmsh create ltm profile http http_totp_admin defaults-from http
```
- [ ] **15. Create TOTP Enrollment VS**
```bash
    tmsh create ltm virtual vs_totp_enroll destination 10.1.1.100:443 ip-protocol tcp 
     profiles replace-all-with { mfa-clientssl { context clientside } http_totp_enroll tcp } 
     source-address-translation { type automap } 
     rules { irule_totp_shared irule_totp_enroll }
```
- [ ] **16. Create TOTP API VS (external + internal)**
```bash
    tmsh create ltm virtual vs_totp_api destination 10.1.1.101:443 ip-protocol tcp 
     profiles replace-all-with { mfa-clientssl { context clientside } http_totp_api tcp } 
     source-address-translation { type automap } 
     rules { irule_totp_shared irule_totp_api }

tmsh create ltm virtual vs_totp_api_internal destination 10.255.255.255:80 ip-protocol tcp 
    profiles replace-all-with { http_totp_api tcp } 
    source-address-translation { type automap } 
    rules { irule_totp_shared irule_totp_api }
```
- [ ] **17. Create Admin UI VS**
```bash
tmsh create ltm virtual vs_totp_admin destination 10.1.1.104:443 ip-protocol tcp 
    profiles replace-all-with { mfa-clientssl { context clientside } http_totp_admin tcp } 
    source-address-translation { type automap } 
    rules { irule_totp_shared irule_totp_admin_ui }
```
- [ ] **18. Create MFA Portal VS (access profile added in Phase 6)**
```bash
tmsh create ltm virtual vs_mfa_portal destination 10.1.1.102:443 ip-protocol tcp 
    profiles replace-all-with { mfa-clientssl { context clientside } http_mfa_portal tcp } 
    source-address-translation { type automap } 
    rules { irule_totp_shared irule_idp_mfa }
```
- [ ] **19. Save configuration**
```bash
tmsh save sys config
```
## Phase 6 --- Access Policies
- [ ] **20. Create HTTP AAA object (GUI only)**
Navigate to: Access then Authentication then HTTP then Create
See Configuration Values for all field values.
- [ ] **21. Create enrollment access profile and policy**
See TOTP Enrollment doc for step-by-step VPE instructions.
Profile: ap_totp_enroll
Policy: Logon Page then Auth (LocalDB or AD) then Allow/Deny
- [ ] **22. Attach enrollment profile to VS**
```bash
tmsh modify ltm virtual vs_totp_enroll profiles add { ap_totp_enroll }
```
- [ ] **23. Create MFA portal access profile and policy**
See MFA Portal doc for step-by-step VPE instructions.
Profile: ap_mfa_portal
Create Redirect-Enroll ending, webtop links, section, and full webtop.
- [ ] **24. Attach MFA portal profile to VS**
```bash
tmsh modify ltm virtual vs_mfa_portal profiles add { ap_mfa_portal }
tmsh save sys config
```
## Phase 7 --- DNS and Testing
- [ ] **25. Configure DNS**
```bash
echo "10.1.1.100 totp-enroll.mfa-demo.local" >> /etc/hosts
echo "10.1.1.101 totp-api.mfa-demo.local" >> /etc/hosts
echo "10.1.1.102 portal.mfa-demo.local" >> /etc/hosts
```
- [ ] **26. Verify API health**
```bash
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}')
curl -s -H "X-API-Key: $API_KEY" http://10.255.255.255/api/v1/health
```
Expected: {"result":"ok"}
- [ ] **27. Test enrollment**
     Browse to https://portal.mfa-demo.local
     Log in with test credentials
     Should redirect to enrollment page
     Scan QR code with authenticator app
     Enter 6-digit code to confirm
- [ ] **28. Test MFA login**
     Browse to https://portal.mfa-demo.local
     Log in with credentials and TOTP code
     Should reach webtop with Reset Authenticator and TOTP Admin links
- [ ] **29. Test Admin UI**
     Browse to https://10.1.1.104
     Verify dashboard shows enrolled user
     Test rate limit reset
## Post-Deployment
- [ ] Restrict Admin UI access (APM profile or source IP filter)
- [ ] Back up encryption key from totp_config_dg securely
- [ ] Configure HA if applicable
- [ ] Review Troubleshooting doc for common issues
## Quick Reference
    | Service | URL | Purpose |
    | --- | --- | --- |
    | MFA Portal | https://portal.mfa-demo.local | User login with MFA |
    | Enrollment | https://totp-enroll.mfa-demo.local/enroll | TOTP enrollment |
    | Re-enrollment | https://totp-enroll.mfa-demo.local/reenroll | Replace authenticator |
    | Admin UI | https://10.1.1.104 | Administration |
    | API Health | http://10.255.255.255/api/v1/health | Internal API check |