# User Management & Experience

## LDBUTIL Usage
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

Screenshots of the Admin WebUI and the Enrollment user experience.

## User & Service Management
![Admin WebUI](/images/totp_admin_ui.png)

## Enrollment User Experience
![User Enrollment](/images/totp_enroll_ui.png)