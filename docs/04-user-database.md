# 04 - User Database

This section covers configuration of the authentication backend for the TOTP MFA solution. Two options are supported: Local DB for lab/testing environments and Active Directory for production deployments.

---

## Authentication Backend Overview

The MFA solution requires an authentication backend to validate user credentials before TOTP verification. The backend is used by APM access policies during the initial login phase.

| Option | Use Case | Pros | Cons |
|--------|----------|------|------|
| Local DB | Lab, testing, PoC, small deployments | Simple setup, no external dependencies | Manual user management, not scalable |
| Active Directory | Production, enterprise | Centralized identity, existing users | Requires AD infrastructure, service account |

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Login Flow                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │   Username + Password   │
                    └─────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │   Authentication AAA    │
                    │   (LocalDB or AD)       │
                    └─────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
            ┌───────────┐               ┌───────────┐
            │  Success  │               │  Failure  │
            └───────────┘               └───────────┘
                    │                           │
                    ▼                           ▼
            ┌───────────────┐           ┌───────────┐
            │ TOTP Verify   │           │   Deny    │
            └───────────────┘           └───────────┘
```

---

## Option A — Local DB (Lab/Testing)

APM Local DB provides a simple user database stored on the BIG-IP. Ideal for lab environments, proof-of-concept deployments, and small-scale implementations.

### Create Local DB Instance

```bash
tmsh create apm aaa local-db-instance mfa_users_db {
    lockout-threshold 5
    auto-unlock-interval 300
}
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| lockout-threshold | 5 | Failed attempts before lockout |
| auto-unlock-interval | 300 | Seconds until automatic unlock (5 minutes) |

### Verify Local DB Instance

```bash
tmsh list apm aaa local-db-instance mfa_users_db
```

Expected output:

```
apm aaa local-db-instance mfa_users_db {
    auto-unlock-interval 300
    lockout-threshold 5
}
```

### Add Users with ldbutil

The `ldbutil` command manages Local DB users. All parameters are mandatory when adding users.

**Basic user:**

```bash
ldbutil --add \
    --instance="/Common/mfa_users_db" \
    --uname="testuser" \
    --password="TestP@ss123!" \
    --first_name="Test" \
    --last_name="User" \
    --email="testuser@mfa-demo.local" \
    --user_groups="mfaUsers" \
    --change_passwd="0" \
    --login_failures="0" \
    --locked_out="0"
```

**Single-line version:**

```bash
ldbutil --add --instance="/Common/mfa_users_db" --uname="testuser" --password="TestP@ss123!" --first_name="Test" --last_name="User" --email="testuser@mfa-demo.local" --user_groups="mfaUsers" --change_passwd="0" --login_failures="0" --locked_out="0"
```

### ldbutil Parameter Reference

| Parameter | Required | Description |
|-----------|----------|-------------|
| --add | Yes | Action: add user |
| --instance | Yes | Full path to Local DB instance |
| --uname | Yes | Username (login name) |
| --password | Yes | Initial password |
| --first_name | Yes | User's first name |
| --last_name | Yes | User's last name |
| --email | Yes | User's email address |
| --user_groups | Yes | Group membership (comma-separated) |
| --change_passwd | Yes | Force password change: 0=no, 1=yes |
| --login_failures | Yes | Current failed login count (set to 0) |
| --locked_out | Yes | Lockout status: 0=no, 1=yes |

### Add Multiple Test Users

**Administrator user:**

```bash
ldbutil --add \
    --instance="/Common/mfa_users_db" \
    --uname="admin1" \
    --password="AdminP@ss123!" \
    --first_name="Admin" \
    --last_name="One" \
    --email="admin1@mfa-demo.local" \
    --user_groups="mfaAdmins,mfaUsers" \
    --change_passwd="0" \
    --login_failures="0" \
    --locked_out="0"
```

**Regular users:**

```bash
ldbutil --add \
    --instance="/Common/mfa_users_db" \
    --uname="user1" \
    --password="UserP@ss123!" \
    --first_name="Regular" \
    --last_name="User1" \
    --email="user1@mfa-demo.local" \
    --user_groups="mfaUsers" \
    --change_passwd="0" \
    --login_failures="0" \
    --locked_out="0"

ldbutil --add \
    --instance="/Common/mfa_users_db" \
    --uname="user2" \
    --password="UserP@ss123!" \
    --first_name="Regular" \
    --last_name="User2" \
    --email="user2@mfa-demo.local" \
    --user_groups="mfaUsers" \
    --change_passwd="0" \
    --login_failures="0" \
    --locked_out="0"
```

### List Users

```bash
ldbutil --list --instance="/Common/mfa_users_db"
```

Expected output:

```
Username: testuser
  First Name: Test
  Last Name: User
  Email: testuser@mfa-demo.local
  Groups: mfaUsers
  Change Password: 0
  Login Failures: 0
  Locked Out: 0

Username: admin1
  First Name: Admin
  Last Name: One
  Email: admin1@mfa-demo.local
  Groups: mfaAdmins,mfaUsers
  Change Password: 0
  Login Failures: 0
  Locked Out: 0
```

### Modify User

**Change password:**

```bash
ldbutil --mod --instance="/Common/mfa_users_db" --uname="testuser" --password="NewP@ss456!"
```

**Unlock user:**

```bash
ldbutil --mod --instance="/Common/mfa_users_db" --uname="testuser" --locked_out="0" --login_failures="0"
```

**Update email:**

```bash
ldbutil --mod --instance="/Common/mfa_users_db" --uname="testuser" --email="newemail@mfa-demo.local"
```

### Delete User

```bash
ldbutil --del --instance="/Common/mfa_users_db" --uname="testuser"
```

### Password Policy Considerations

Local DB does not enforce password complexity. Implement organizational password requirements through documentation and user training. Recommended minimum:

- 12+ characters
- Uppercase and lowercase letters
- Numbers
- Special characters
- No dictionary words

---

## Option B — Active Directory (Production)

Active Directory integration enables authentication against your existing enterprise directory.

### Prerequisites

Before configuring AD authentication:

- [ ] AD domain controller(s) accessible from BIG-IP
- [ ] Service account with read access to directory
- [ ] DNS resolution for AD domain
- [ ] Firewall rules allowing LDAP/LDAPS traffic

### Network Requirements

| Protocol | Port | Source | Destination | Purpose |
|----------|------|--------|-------------|---------|
| LDAP | 389/TCP | BIG-IP | Domain Controller | Standard LDAP |
| LDAPS | 636/TCP | BIG-IP | Domain Controller | Secure LDAP |
| Kerberos | 88/TCP,UDP | BIG-IP | Domain Controller | Authentication |
| DNS | 53/TCP,UDP | BIG-IP | DNS Server | Name resolution |

### Create AD AAA Server (GUI)

AD AAA configuration requires the GUI for full functionality.

1. Navigate to: **Access → Authentication → Active Directory → Create**

2. Configure General Properties:

| Field | Example Value | Description |
|-------|---------------|-------------|
| Name | mfa_ad_aaa | AAA server object name |
| Domain Name | corp.example.com | AD domain FQDN |
| Server Connection | Direct | Connection method |
| Domain Controller | dc01.corp.example.com | Primary DC FQDN or IP |

3. Configure Credentials:

| Field | Example Value | Description |
|-------|---------------|-------------|
| Admin Name | svc_bigip@corp.example.com | Service account UPN |
| Admin Password | (service account password) | Service account password |

4. Configure Optional Settings:

| Field | Example Value | Description |
|-------|---------------|-------------|
| Timeout | 15 | Connection timeout (seconds) |
| LDAP Timeout | 15 | LDAP query timeout (seconds) |

5. Click **Finished**

### Create AD AAA Server (tmsh)

Basic AD AAA can be created via tmsh, though some options require GUI:

```bash
tmsh create apm aaa active-directory mfa_ad_aaa {
    domain corp.example.com
    domain-controller dc01.corp.example.com
    admin-name "svc_bigip@corp.example.com"
    admin-password "ServiceAccountP@ss!"
    timeout 15
}
```

### Verify AD AAA Server

```bash
tmsh list apm aaa active-directory mfa_ad_aaa
```

### Test AD Connectivity

From the BIG-IP command line:

```bash
# Test DNS resolution
nslookup corp.example.com

# Test LDAP connectivity
nc -zv dc01.corp.example.com 389

# Test LDAPS connectivity
nc -zv dc01.corp.example.com 636

# Test Kerberos
nc -zv dc01.corp.example.com 88
```

### Multiple Domain Controllers

For high availability, configure multiple domain controllers:

**Via GUI:**

In the Domain Controller field, enter multiple DCs separated by spaces:
```
dc01.corp.example.com dc02.corp.example.com
```

**Via tmsh:**

```bash
tmsh modify apm aaa active-directory mfa_ad_aaa {
    domain-controller "dc01.corp.example.com dc02.corp.example.com"
}
```

### Secure LDAP (LDAPS)

For encrypted LDAP communication:

1. Import the AD CA certificate:

```bash
tmsh install sys crypto cert ad-ca-cert from-local-file /var/tmp/ad-ca-cert.crt
```

2. Configure AD AAA for LDAPS via GUI:

| Field | Value |
|-------|-------|
| Use SSL | Enabled |
| SSL CA Certificate | ad-ca-cert |
| SSL Server Certificate | (optional, for mutual TLS) |

### Service Account Requirements

The AD service account requires minimal permissions:

| Permission | Scope | Purpose |
|------------|-------|---------|
| Read | User objects | Query user attributes |
| Read | Group objects | Query group membership |

**Recommended:** Create a dedicated service account with read-only access. Do not use a domain administrator account.

**Example AD group membership:**
- Domain Users (default)
- No administrative groups required

---

## AAA Server Selection in Access Policy

The AAA server (Local DB or AD) is referenced in the Access Policy via the authentication action.

### Local DB Auth Action

In VPE, add **LocalDB Auth** action:

| Field | Value |
|-------|-------|
| AAA Server | /Common/mfa_users_db |

### AD Auth Action

In VPE, add **AD Auth** action:

| Field | Value |
|-------|-------|
| AAA Server | /Common/mfa_ad_aaa |

See [08 - MFA Portal](08-mfa-portal.md) for complete access policy configuration.

---

## User Groups

User groups can be used for authorization decisions in access policies.

### Local DB Groups

Groups are assigned during user creation with the `--user_groups` parameter:

```bash
# Single group
--user_groups="mfaUsers"

# Multiple groups
--user_groups="mfaAdmins,mfaUsers"
```

### AD Groups

AD group membership is automatically available in session variables after successful authentication:

| Session Variable | Content |
|------------------|---------|
| session.ad.last.attr.memberOf | DN list of group memberships |
| session.ad.last.attr.primaryGroupID | Primary group ID |

Use **AD Group Resource Assign** or **Empty** action with branch rules to check group membership.

---

## Hybrid Configuration

For environments transitioning from Local DB to AD, or requiring both:

1. Create both AAA servers:
   - mfa_users_db (Local DB)
   - mfa_ad_aaa (Active Directory)

2. In access policy, use branching logic:
   - Check username format (UPN vs simple name)
   - Route to appropriate AAA server

3. Or maintain separate access profiles:
   - ap_mfa_portal_local (Local DB)
   - ap_mfa_portal_ad (Active Directory)

---

## Troubleshooting

### Local DB Issues

**User not found:**

```bash
# Verify user exists
ldbutil --list --instance="/Common/mfa_users_db" | grep -A7 "testuser"
```

**User locked out:**

```bash
# Check lockout status
ldbutil --list --instance="/Common/mfa_users_db" | grep -A7 "testuser" | grep "Locked"

# Unlock user
ldbutil --mod --instance="/Common/mfa_users_db" --uname="testuser" --locked_out="0" --login_failures="0"
```

**Wrong instance path:**

The instance path must be fully qualified: `/Common/mfa_users_db`

### Active Directory Issues

**Connection timeout:**

```bash
# Test network connectivity
ping dc01.corp.example.com
nc -zv dc01.corp.example.com 389
```

**Authentication failed:**

```bash
# Test service account credentials manually
ldapsearch -x -H ldap://dc01.corp.example.com -D "svc_bigip@corp.example.com" -W -b "dc=corp,dc=example,dc=com" "(sAMAccountName=testuser)"
```

**SSL certificate errors:**

```bash
# Test LDAPS connection
openssl s_client -connect dc01.corp.example.com:636

# Verify CA certificate is imported
tmsh list sys crypto cert ad-ca-cert
```

**DNS resolution failure:**

```bash
# Check DNS configuration
tmsh list sys dns

# Test resolution
nslookup corp.example.com
dig dc01.corp.example.com
```

### APM Session Debugging

Enable APM debug logging temporarily:

```bash
# Enable debug logging
tmsh modify sys db log.access.level value debug

# View logs
tail -f /var/log/apm

# Disable debug logging (important!)
tmsh modify sys db log.access.level value warning
```

---

## Security Considerations

### Local DB

- Passwords stored in BIG-IP configuration
- Back up configuration securely
- Use strong passwords
- Implement lockout thresholds
- Regular password rotation

### Active Directory

- Use dedicated service account
- Minimal required permissions
- Use LDAPS when possible
- Monitor service account for compromise
- Regular credential rotation

### General

- Implement account lockout policies
- Monitor authentication failures
- Log authentication events
- Regular access reviews

---

## Configuration Summary

### Local DB Deployment

| Component | Value |
|-----------|-------|
| Instance Name | mfa_users_db |
| Lockout Threshold | 5 attempts |
| Auto-Unlock Interval | 300 seconds |
| User Groups | mfaUsers, mfaAdmins |

### Active Directory Deployment

| Component | Value |
|-----------|-------|
| AAA Server Name | mfa_ad_aaa |
| Domain | corp.example.com |
| Domain Controller | dc01.corp.example.com |
| Service Account | svc_bigip@corp.example.com |
| Protocol | LDAP (389) or LDAPS (636) |

---

## Save Configuration

```bash
tmsh save sys config