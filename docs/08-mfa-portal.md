# 08 - MFA Portal

This section covers the MFA portal configuration including the virtual server, HTTP AAA integration, access policy with enrollment check macro, TOTP verification, and webtop resources for user self-service.

---

## MFA Portal Architecture Overview

The MFA portal is the primary user-facing entry point that combines credential authentication with TOTP verification:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MFA Portal Flow                                      │
└─────────────────────────────────────────────────────────────────────────────┘

     User                      MFA Portal                    Backend Services
       │                           │                                │
       │  1. Access portal         │                                │
       ├──────────────────────────►│                                │
       │                           │                                │
       │  2. Login page            │                                │
       │◄──────────────────────────┤                                │
       │                           │                                │
       │  3. Username + Password   │                                │
       ├──────────────────────────►│                                │
       │                           │                                │
       │                           │  4. Validate credentials       │
       │                           ├───────────────────────────────►│
       │                           │     (LocalDB / AD)             │
       │                           │◄───────────────────────────────┤
       │                           │                                │
       │                           │  5. Check enrollment           │
       │                           ├───────────────────────────────►│
       │                           │     (TOTP API)                 │
       │                           │◄───────────────────────────────┤
       │                           │                                │
       │     [If not enrolled]     │                                │
       │  6a. Redirect to enroll   │                                │
       │◄──────────────────────────┤                                │
       │                           │                                │
       │     [If enrolled]         │                                │
       │  6b. TOTP code page       │                                │
       │◄──────────────────────────┤                                │
       │                           │                                │
       │  7. Enter TOTP code       │                                │
       ├──────────────────────────►│                                │
       │                           │                                │
       │                           │  8. Verify TOTP                │
       │                           ├───────────────────────────────►│
       │                           │     (HTTP AAA → Internal API)  │
       │                           │◄───────────────────────────────┤
       │                           │                                │
       │  9. Webtop / Resources    │                                │
       │◄──────────────────────────┤                                │
       │                           │                                │
```

### Component Summary

| Component | Purpose |
|-----------|---------|
| vs_mfa_portal | Virtual server handling portal traffic |
| ap_mfa_portal | Access profile with MFA policy |
| http_aaa_totp_verify | HTTP AAA for TOTP verification |
| Enrollment Check Macro | VPE macro to check enrollment status |
| Redirect-Enroll Ending | Custom ending to redirect unenrolled users |
| webtop_mfa | Full webtop for authenticated users |
| irule_idp_mfa | iRule for portal customization |

---

## HTTP AAA Configuration

The HTTP AAA object enables APM to verify TOTP codes via the internal API.

### Create HTTP AAA (GUI Only)

HTTP AAA with Custom Post type must be created via the GUI.

1. Navigate to: **Access → Authentication → HTTP → Create**

2. Configure General Properties:

| Field | Value |
|-------|-------|
| Name | http_aaa_totp_verify |
| Authentication Type | Custom Post |

3. Configure Custom Post Settings:

| Field | Value |
|-------|-------|
| Start URI | http://10.255.255.255:80 |
| Form Action | /api/v1/verify |
| Form Parameter For User Name | username |
| Form Parameter For Password | code |

4. Configure Custom Post Body:

```
username=%{session.logon.last.username}&code=%{session.logon.last.totp_code}
```

5. Configure Success Detection:

| Field | Value |
|-------|-------|
| Successful Logon Detection Match Type | By Specific String in Response |
| Successful Logon Detection Match Value | "success":true |

6. Click **Finished**

### HTTP AAA Configuration Reference

| Setting | Value | Description |
|---------|-------|-------------|
| Start URI | http://10.255.255.255:80 | Internal API endpoint (non-routable) |
| Form Action | /api/v1/verify | API verification path |
| Form Body | username=%{session.logon.last.username}&code=%{session.logon.last.totp_code} | Session variables for credentials |
| Success Pattern | "success":true | JSON response indicating valid code |

### Verify HTTP AAA

```bash
tmsh list apm aaa http http_aaa_totp_verify
```

> **Note:** The HTTP AAA connects to the internal API VS (10.255.255.255:80) which is non-routable from outside the BIG-IP. This provides security isolation for the verification endpoint.

---

## iRule Configuration

### irule_idp_mfa

The MFA portal iRule handles portal-specific logic and customization.

Create via GUI: **Local Traffic → iRules → iRule List → Create**

- Name: `irule_idp_mfa`
- Definition: (paste content from `irules/irule_idp_mfa.tcl`)

### Verify iRule

```bash
tmsh list ltm rule irule_idp_mfa
```

---

## HTTP Profile

Create a dedicated HTTP profile for the MFA portal:

```bash
tmsh create ltm profile http http_mfa_portal defaults-from http
```

---

## Virtual Server

### Create MFA Portal Virtual Server

```bash
tmsh create ltm virtual vs_mfa_portal {
    destination 10.1.1.102:443
    ip-protocol tcp
    profiles replace-all-with {
        mfa-clientssl { context clientside }
        http_mfa_portal
        tcp
    }
    source-address-translation { type automap }
    rules { irule_totp_shared irule_idp_mfa }
}
```

> **Note:** The access profile is attached after creation in the Access Policy section.

### Verify Virtual Server

```bash
tmsh list ltm virtual vs_mfa_portal
```

---

## Access Profile

### Create Access Profile

```bash
tmsh create apm profile access ap_mfa_portal {
    accept-languages add { en }
    default-language en
    type all
}
```

### Access Policy Overview

The MFA portal access policy implements a multi-stage authentication flow:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Access Policy Flow                                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────┐    ┌────────────┐    ┌────────────┐    ┌──────────────────┐
│ Start │───►│ Logon Page │───►│ LocalDB/AD │───►│ Enrollment Check │
└───────┘    │ (user/pass)│    │ Auth       │    │ Macro            │
             └────────────┘    └────────────┘    └──────────────────┘
                                     │                    │
                                     │ Failure            ├─────────────────┐
                                     ▼                    │                 │
                                ┌────────┐                │                 │
                                │ Deny   │                │                 │
                                └────────┘          IsEnrolled         NotEnrolled
                                                          │                 │
                                                          ▼                 ▼
                                                   ┌─────────────┐   ┌──────────────┐
                                                   │ TOTP Logon  │   │ Redirect to  │
                                                   │ Page        │   │ Enrollment   │
                                                   └─────────────┘   │ (Purple End) │
                                                          │          └──────────────┘
                                                          ▼
                                                   ┌─────────────┐
                                                   │ HTTP Auth   │
                                                   │ (TOTP API)  │
                                                   └─────────────┘
                                                          │
                                                    ┌─────┴─────┐
                                                    │           │
                                              Success       Failure
                                                    │           │
                                                    ▼           ▼
                                             ┌──────────┐ ┌────────┐
                                             │ Advanced │ │ Deny   │
                                             │ Resource │ └────────┘
                                             │ Assign   │
                                             └──────────┘
                                                    │
                                                    ▼
                                             ┌──────────┐
                                             │ Allow    │
                                             │ (Webtop) │
                                             └──────────┘
```

---

## Configure Access Policy (VPE)

### Open Visual Policy Editor

1. Navigate to: **Access → Profiles / Policies → Access Profiles (Per-Session Policies)**
2. Click **ap_mfa_portal**
3. Click **Edit Access Policy for Profile "ap_mfa_portal"**

### Step 1: Add Logon Page

1. Click the **+** after **Start**
2. Select **Logon Page** from the Logon tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | MFA Login |

4. Configure form fields:

| Field # | Post Variable | Session Variable | Type |
|---------|---------------|------------------|------|
| 1 | username | session.logon.last.username | text |
| 2 | password | session.logon.last.password | password |

5. Click **Save**

### Step 2: Add Primary Authentication

**For Local DB:**

1. Click the **+** after Logon Page (on the main branch)
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

### Step 3: Create Enrollment Check Macro

The enrollment check macro queries the API to determine if a user is enrolled.

#### 3a. Create Macro

1. Click **Add New Macro** at the bottom of the VPE
2. Configure:

| Field | Value |
|-------|-------|
| Name | Enrollment_Check |

3. Click **Save**

#### 3b. Configure Macro Terminals

1. Click the **+** next to the macro name
2. Click **Edit Terminals**
3. Add terminal:

| Terminal Name | Color |
|---------------|-------|
| IsEnrolled | Green |
| NotEnrolled | Yellow |

4. Click **Save**

#### 3c. Add HTTP Auth to Macro

1. Inside the macro, click **+** after **In**
2. Select **HTTP Auth** from Authentication tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | Check Enrollment |
| AAA Server | (create inline or use separate) |

**Create inline HTTP Auth for enrollment check:**

For the enrollment check, we need a different HTTP AAA that calls the `/api/v1/check` endpoint.

**Option A: Use iRule/Variable Workaround**

Since HTTP AAA is limited, use a simpler approach with an Empty action and iRule-set variable.

1. Instead of HTTP Auth, add **Empty** action
2. Name it: `Check Enrollment Status`
3. Click **Branch Rules** tab
4. Add branch rule:

| Name | Expression |
|------|------------|
| IsEnrolled | expr { [mcget {session.custom.totp_enrolled}] == 1 } |

5. Connect branches:
   - IsEnrolled → IsEnrolled terminal (green)
   - fallback → NotEnrolled terminal (yellow)

**Option B: Use iRule to Set Session Variable**

The `irule_idp_mfa` iRule can query the API and set the session variable before the policy runs. This is the recommended approach.

The iRule sets `session.custom.totp_enrolled` to `1` if enrolled, `0` if not.

#### 3d. Connect Macro Branches

1. Connect **IsEnrolled** branch to green terminal
2. Connect **fallback** (NotEnrolled) branch to yellow terminal

### Step 4: Add Enrollment Check Macro to Main Policy

1. In the main policy, click **+** after LocalDB/AD Auth (Successful branch)
2. Select **Macros** tab
3. Select **Enrollment_Check**
4. Click **Add Item**

### Step 5: Create Redirect-Enroll Ending

For users not enrolled, redirect to the enrollment page.

1. On the **NotEnrolled** branch from the macro, click the ending
2. Click **Change**
3. Select **Redirect** from the General Purpose tab
4. Configure:

| Field | Value |
|-------|-------|
| Name | Redirect-Enroll |
| Color | Purple |
| Redirect Type | Custom |
| URL | https://totp-enroll.mfa-demo.local:443/enroll |

5. Click **Save**

### Step 6: Add TOTP Logon Page

1. On the **IsEnrolled** branch, click **+**
2. Select **Logon Page** from Logon tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | TOTP Code |

4. Configure form fields (remove password, add TOTP field):

| Field # | Post Variable | Session Variable | Type | Read Only |
|---------|---------------|------------------|------|-----------|
| 1 | username | session.logon.last.username | text | Yes |
| 2 | totp_code | session.logon.last.totp_code | password | No |

5. Customize field labels:
   - Field 1 Label: `Username`
   - Field 2 Label: `TOTP Code`

6. Click **Save**

### Step 7: Add HTTP Auth for TOTP Verification

1. After TOTP Logon Page, click **+**
2. Select **HTTP Auth** from Authentication tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | TOTP Verify |
| AAA Server | /Common/http_aaa_totp_verify |

4. Click **Save**

### Step 8: Add Advanced Resource Assign

1. On the **Successful** branch after HTTP Auth, click **+**
2. Select **Advanced Resource Assign** from Assignment tab
3. Configure:

| Field | Value |
|-------|-------|
| Name | Assign Webtop |

4. Click **Add new entry**
5. Click **Add/Delete** next to the entry
6. Select:
   - **Webtop** tab: `webtop_mfa`
   - **Webtop Links** tab: Select desired links

7. Click **Update**, then **Save**

### Step 9: Configure Endings

1. After Advanced Resource Assign, ensure ending is **Allow**
2. On HTTP Auth **Failure** branch, ensure ending is **Deny**
3. On LocalDB/AD Auth **Failure** branch, ensure ending is **Deny**

### Step 10: Apply Access Policy

1. Click **Apply Access Policy** (yellow banner at top of VPE)

---

## Webtop Configuration

### Create Full Webtop

```bash
tmsh create apm profile webtop webtop_mfa {
    type full
}
```

### Create Webtop Links

**Reset Authenticator Link:**

```bash
tmsh create apm resource webtop-link link_reset_authenticator {
    application-uri "https://totp-enroll.mfa-demo.local:443/reenroll"
    caption "Reset Authenticator"
    description "Replace your current TOTP authenticator"
}
```

**TOTP Admin Link (Optional - for administrators):**

```bash
tmsh create apm resource webtop-link link_totp_admin {
    application-uri "https://totp-admin.mfa-demo.local:443/"
    caption "TOTP Admin"
    description "TOTP Administration Console"
}
```

### Create Webtop Section (Optional)

Organize links into sections:

```bash
tmsh create apm resource webtop-section section_mfa_tools {
    caption "MFA Tools"
}
```

### Verify Webtop Resources

```bash
tmsh list apm profile webtop webtop_mfa
tmsh list apm resource webtop-link
tmsh list apm resource webtop-section
```

---

## Attach Access Profile to Virtual Server

```bash
tmsh modify ltm virtual vs_mfa_portal profiles add { ap_mfa_portal }
```

### Verify Attachment

```bash
tmsh list ltm virtual vs_mfa_portal profiles
```

Expected output includes:

```
profiles {
    ap_mfa_portal { }
    http_mfa_portal { }
    mfa-clientssl {
        context clientside
    }
    tcp { }
}
```

---

## Session Variables Reference

The access policy uses the following session variables:

| Variable | Set By | Purpose |
|----------|--------|---------|
| session.logon.last.username | Logon Page | Username for authentication |
| session.logon.last.password | Logon Page | Password for primary auth |
| session.logon.last.totp_code | TOTP Logon Page | TOTP code for verification |
| session.custom.totp_enrolled | iRule | Enrollment status (1/0) |
| session.localdb.last.result | LocalDB Auth | Auth result code |
| session.ad.last.result | AD Auth | Auth result code |

---

## Customization Options

### Custom Logon Page Styling

Customize the logon page appearance via APM Customization:

1. Navigate to: **Access → Profiles / Policies → Customization**
2. Select **Access Profile** → **ap_mfa_portal**
3. Customize:
   - Logo
   - Colors
   - Header/Footer text
   - Field labels

### Custom Error Messages

Configure custom messages for authentication failures:

1. In VPE, click on **Deny** ending
2. Click **Edit**
3. Customize the message displayed to users

### Session Timeout Settings

Adjust session timeouts in the access profile:

```bash
tmsh modify apm profile access ap_mfa_portal {
    inactivity-timeout 900
    access-policy-timeout 300
    max-session-timeout 604800
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| inactivity-timeout | 900 | Seconds of inactivity before logout |
| access-policy-timeout | 300 | Seconds to complete access policy |
| max-session-timeout | 604800 | Maximum session duration (7 days) |

---

## Testing the MFA Portal

### Test Prerequisites

- [ ] Test user exists in authentication backend
- [ ] Test user is enrolled for TOTP (or not, to test redirect)
- [ ] Authenticator app configured with test user's TOTP
- [ ] DNS resolution for portal.mfa-demo.local

### Test 1: Unenrolled User Flow

1. Create new test user (not enrolled):
   ```bash
   ldbutil --add --instance="/Common/mfa_users_db" \
       --uname="newuser" --password="NewP@ss123!" \
       --first_name="New" --last_name="User" \
       --email="newuser@mfa-demo.local" \
       --user_groups="mfaUsers" --change_passwd="0" \
       --login_failures="0" --locked_out="0"
   ```

2. Browse to `https://portal.mfa-demo.local`

3. Enter credentials:
   - Username: `newuser`
   - Password: `NewP@ss123!`

4. **Expected:** Redirect to `https://totp-enroll.mfa-demo.local/enroll`

5. Complete enrollment

6. **Expected:** Redirect back to portal or success message

### Test 2: Enrolled User Flow

1. Browse to `https://portal.mfa-demo.local`

2. Enter credentials:
   - Username: `testuser` (enrolled user)
   - Password: `TestP@ss123!`

3. **Expected:** TOTP code page displayed

4. Enter TOTP code from authenticator app

5. **Expected:** Webtop displayed with links

### Test 3: Invalid TOTP Code

1. Log in with valid credentials

2. Enter incorrect TOTP code: `000000`

3. **Expected:** Authentication failure, access denied

4. Check rate limiting:
   ```bash
   curl -sk -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"
   ```

### Test 4: Webtop Links

1. Log in successfully to webtop

2. Click "Reset Authenticator"

3. **Expected:** Redirect to re-enrollment page

4. Complete re-enrollment with new QR code

5. **Expected:** Old authenticator codes no longer work

### Test 5: Session Timeout

1. Log in successfully

2. Wait for inactivity timeout (default 15 minutes)

3. **Expected:** Session expired, redirected to login

---

## Troubleshooting

### Login Page Not Appearing

```bash
# Check virtual server status
tmsh show ltm virtual vs_mfa_portal

# Check access profile attached
tmsh list ltm virtual vs_mfa_portal profiles

# Check APM provisioning
tmsh show sys provision | grep apm
```

### Primary Authentication Failing

```bash
# Check APM logs
tail -f /var/log/apm | grep ap_mfa_portal

# Test LocalDB user
ldbutil --list --instance="/Common/mfa_users_db" | grep testuser

# Check AAA server
tmsh list apm aaa local-db-instance mfa_users_db
```

### Enrollment Check Not Working

```bash
# Test API enrollment check
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"

# Check session variable is being set
# Enable APM debug logging temporarily
tmsh modify sys db log.access.level value debug
tail -f /var/log/apm
```

### TOTP Verification Failing

```bash
# Test API verification directly
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/verify?username=testuser&code=123456"

# Check HTTP AAA configuration
tmsh list apm aaa http http_aaa_totp_verify

# Verify internal API VS is responding
curl -s "http://10.255.255.255:80/api/v1/health"

# Check time synchronization
ntpq -p
```

### Redirect to Enrollment Not Working

```bash
# Verify redirect ending configuration in VPE

# Check URL is correct
# Should be: https://totp-enroll.mfa-demo.local:443/enroll

# Test enrollment VS is accessible
curl -sk "https://totp-enroll.mfa-demo.local:443/" -I
```

### Webtop Not Displaying

```bash
# Check webtop profile exists
tmsh list apm profile webtop webtop_mfa

# Check webtop links exist
tmsh list apm resource webtop-link

# Verify Advanced Resource Assign in VPE has webtop selected
```

### Session Variable Issues

```bash
# Enable APM session variable logging
tmsh modify sys db log.access.level value debug

# Check session variables in logs
tail -f /var/log/apm | grep -E "session\.(logon|custom)"

# Disable debug when done
tmsh modify sys db log.access.level value warning
```

---

## Log Messages

MFA portal-related log patterns (see [Log Reference](appendicies/log-reference.md)):

| Pattern | Meaning |
|---------|---------|
| `MFA\|<sid>:Enrollment check` | Enrollment status query |
| `MFA\|<sid>:User enrolled` | User has TOTP configured |
| `MFA\|<sid>:User not enrolled` | User needs enrollment |
| `MFA\|<sid>:TOTP verified` | Successful TOTP validation |
| `MFA\|<sid>:TOTP failed` | Invalid TOTP code |

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
| HTTP AAA | http_aaa_totp_verify |
| MFA iRule | irule_idp_mfa |
| HTTP Profile | http_mfa_portal |
| Virtual Server | vs_mfa_portal (10.1.1.102:443) |
| Access Profile | ap_mfa_portal |
| Webtop | webtop_mfa |
| Webtop Link | link_reset_authenticator |
| Webtop Link | link_totp_admin (optional) |

### Access Policy Summary

| Stage | Component | Branches |
|-------|-----------|----------|
| 1 | Logon Page | → |
| 2 | LocalDB/AD Auth | Success / Failure |
| 3 | Enrollment Check Macro | IsEnrolled / NotEnrolled |
| 4a | Redirect-Enroll (purple) | ← NotEnrolled |
| 4b | TOTP Logon Page | ← IsEnrolled |
| 5 | HTTP Auth (TOTP) | Success / Failure |
| 6 | Advanced Resource Assign | → |
| 7 | Allow | End |

---

## Next Steps

Proceed to [09 - HA Configuration](09-ha-configuration.md) to configure high availability with device trust, device groups, and traffic group failover.