# 11 - Testing

This section covers comprehensive testing procedures, test matrices, validation scripts, and troubleshooting guidance for the TOTP MFA solution.

---

## Testing Overview

Testing should be performed in phases to validate each component before integration testing:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Testing Phases                                       │
└─────────────────────────────────────────────────────────────────────────────┘

  Phase 1              Phase 2              Phase 3              Phase 4
  Infrastructure       Component            Integration          Production
  ─────────────        ─────────            ───────────          ──────────
  • Network            • API endpoints      • Enrollment flow    • Load testing
  • SSL/TLS            • iRules             • MFA login flow     • Failover
  • DNS                • Access policies    • Re-enrollment      • Monitoring
  • NTP                • Alert scripts      • Admin functions    • User acceptance
```

---

## Phase 1: Infrastructure Testing

### Test 1.1: Network Connectivity

**Objective:** Verify network configuration and routing.

```bash
# Test external VLAN connectivity
ping -c 3 10.1.1.254  # Default gateway

# Test internal VLAN (from BIG-IP)
ping -c 3 10.255.255.254  # Internal self-IP

# Test DNS resolution
nslookup portal.mfa-demo.local
nslookup totp-enroll.mfa-demo.local
nslookup totp-api.mfa-demo.local
nslookup totp-admin.mfa-demo.local
```

**Expected Results:**

| Test | Expected |
|------|----------|
| Gateway ping | Response received |
| Internal self-IP | Response received |
| DNS resolution | All FQDNs resolve to correct IPs |

### Test 1.2: SSL/TLS Certificates

**Objective:** Verify SSL certificates are valid and properly configured.

```bash
# Test certificate on enrollment VS
openssl s_client -connect totp-enroll.mfa-demo.local:443 -servername totp-enroll.mfa-demo.local < /dev/null 2>/dev/null | openssl x509 -noout -subject -dates

# Test certificate on API VS
openssl s_client -connect totp-api.mfa-demo.local:443 -servername totp-api.mfa-demo.local < /dev/null 2>/dev/null | openssl x509 -noout -subject -dates

# Test certificate on portal VS
openssl s_client -connect portal.mfa-demo.local:443 -servername portal.mfa-demo.local < /dev/null 2>/dev/null | openssl x509 -noout -subject -dates

# Test certificate on admin VS
openssl s_client -connect totp-admin.mfa-demo.local:443 -servername totp-admin.mfa-demo.local < /dev/null 2>/dev/null | openssl x509 -noout -subject -dates
```

**Expected Results:**

| Test | Expected |
|------|----------|
| Subject | CN=*.mfa-demo.local or matching SAN |
| Not Before | Past date |
| Not After | Future date (not expired) |

### Test 1.3: NTP Synchronization

**Objective:** Verify time synchronization (critical for TOTP).

```bash
# Check NTP status
ntpq -p

# Check system time
date

# Compare with known accurate source
curl -s "http://worldtimeapi.org/api/ip" | grep -o '"datetime":"[^"]*"'
```

**Expected Results:**

| Test | Expected |
|------|----------|
| ntpq -p | `*` next to active server |
| Time drift | < 5 seconds from accurate source |

### Test 1.4: Virtual Server Status

**Objective:** Verify all virtual servers are available.

```bash
# Check VS status
tmsh show ltm virtual vs_totp_enroll | grep -E "Availability|State"
tmsh show ltm virtual vs_totp_api | grep -E "Availability|State"
tmsh show ltm virtual vs_totp_api_internal | grep -E "Availability|State"
tmsh show ltm virtual vs_mfa_portal | grep -E "Availability|State"
tmsh show ltm virtual vs_totp_admin | grep -E "Availability|State"
```

**Expected Results:**

| Virtual Server | Availability | State |
|----------------|--------------|-------|
| vs_totp_enroll | available | enabled |
| vs_totp_api | available | enabled |
| vs_totp_api_internal | available | enabled |
| vs_mfa_portal | available | enabled |
| vs_totp_admin | available | enabled |

---

## Phase 2: Component Testing

### Test 2.1: API Health Endpoint

**Objective:** Verify API is responding correctly.

```bash
# Get API key
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

# Test external API
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"

# Test internal API
curl -s -H "X-API-Key: $API_KEY" \
    "http://10.255.255.255:80/api/v1/health"
```

**Expected Results:**

```json
{"status":"ok"}
```

### Test 2.2: API Authentication

**Objective:** Verify API key authentication works correctly.

```bash
# Test with valid API key
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"

# Test without API key
curl -sk "https://totp-api.mfa-demo.local:443/api/v1/health"

# Test with invalid API key
curl -sk -H "X-API-Key: invalid-key" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

**Expected Results:**

| Test | Expected Response | HTTP Status |
|------|-------------------|-------------|
| Valid key | `{"status":"ok"}` | 200 |
| No key | `{"error":"unauthorized"...}` | 401 |
| Invalid key | `{"error":"unauthorized"...}` | 401 |

### Test 2.3: API Endpoints

**Objective:** Verify all API endpoints function correctly.

```bash
# Enrollment check (non-existent user)
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=nonexistent"

# Rate status (non-existent user)
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=nonexistent"

# Rate summary
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-summary"

# Populate table
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"
```

**Expected Results:**

| Endpoint | Expected Response |
|----------|-------------------|
| /check (not enrolled) | `{"enrolled":false,...}` |
| /status | `{"username":...,"attempts":...}` |
| /rate-summary | `{"verify":{...},"enroll":{...}}` |
| /populate-table | `{"success":true,...}` |

### Test 2.4: Alert System

**Objective:** Verify alert scripts trigger correctly.

```bash
# Check alertd status
bigstart status alertd

# Verify alert configuration
grep "TOTP_" /config/user_alert.conf

# Test enrollment trigger
logger -p local0.alert "TOTP_ENROLL_TRIGGER:alerttest"
sleep 3
grep "alerttest" /var/log/ltm | tail -5

# Test unenrollment trigger
logger -p local0.alert "TOTP_UNENROLL_TRIGGER:alerttest"
sleep 3
grep "alerttest" /var/log/ltm | tail -5
```

**Expected Results:**

| Test | Expected |
|------|----------|
| alertd status | Running |
| Alert config | Contains TOTP_ENROLL_TRIGGER and TOTP_UNENROLL_TRIGGER |
| Enrollment trigger | Log shows script execution |
| Unenrollment trigger | Log shows script execution |

### Test 2.5: Data Groups

**Objective:** Verify data groups are configured correctly.

```bash
# Check config data group
tmsh list ltm data-group internal totp_config_dg records

# Verify required keys exist
tmsh list ltm data-group internal totp_config_dg records | grep -E "encryption_key|issuer|api_key"

# Check secrets data group exists
tmsh list ltm data-group internal totp_secrets_dg
```

**Expected Results:**

| Data Group | Expected |
|------------|----------|
| totp_config_dg | Contains encryption_key, issuer, api_key, rate limits |
| totp_secrets_dg | Exists (may be empty initially) |

### Test 2.6: iRules

**Objective:** Verify iRules are attached and error-free.

```bash
# List iRules
tmsh list ltm rule one-line | grep totp

# Check for syntax errors (reload test)
tmsh load sys config verify

# Check iRule stats
tmsh show ltm rule irule_totp_shared stats
tmsh show ltm rule irule_totp_enroll stats
tmsh show ltm rule irule_totp_api stats
tmsh show ltm rule irule_idp_mfa stats
tmsh show ltm rule irule_totp_admin_ui stats
```

**Expected Results:**

| Test | Expected |
|------|----------|
| iRules list | All 5 iRules present |
| Config verify | No errors |
| Stats | No Tcl errors in counters |

### Test 2.7: Access Policies

**Objective:** Verify APM access policies are configured.

```bash
# List access profiles
tmsh list apm profile access one-line | grep -E "ap_totp|ap_mfa"

# Check policy state
tmsh show apm profile access ap_totp_enroll | grep -E "Status|State"
tmsh show apm profile access ap_mfa_portal | grep -E "Status|State"
```

**Expected Results:**

| Access Profile | Status |
|----------------|--------|
| ap_totp_enroll | Applied |
| ap_mfa_portal | Applied |

---

## Phase 3: Integration Testing

### Test 3.1: New User Enrollment Flow

**Objective:** Verify complete enrollment flow for new user.

**Prerequisites:**
- Test user exists in authentication backend
- Authenticator app ready on mobile device

**Steps:**

1. **Create test user (if using Local DB):**
   ```bash
   ldbutil --add --instance="/Common/mfa_users_db" \
       --uname="enrolltest" --password="EnrollP@ss123!" \
       --first_name="Enroll" --last_name="Test" \
       --email="enrolltest@mfa-demo.local" \
       --user_groups="mfaUsers" --change_passwd="0" \
       --login_failures="0" --locked_out="0"
   ```

2. **Access enrollment page:**
   ```
   https://totp-enroll.mfa-demo.local/enroll
   ```

3. **Complete login:**
   - Username: `enrolltest`
   - Password: `EnrollP@ss123!`

4. **Verify QR code displays:**
   - QR code should be visible
   - Manual entry code should be displayed
   - Issuer should match configured value

5. **Scan QR code:**
   - Open authenticator app
   - Scan QR code
   - Verify account appears in app

6. **Confirm enrollment:**
   - Enter 6-digit code from authenticator
   - Submit confirmation

7. **Verify success:**
   - Success message displayed
   - Check API for enrollment:
     ```bash
     curl -sk -H "X-API-Key: $API_KEY" \
         "https://totp-api.mfa-demo.local:443/api/v1/check?username=enrolltest"
     ```

8. **Verify persistence:**
   ```bash
   # Wait for alert script
   sleep 5
   
   # Check data group
   tmsh list ltm data-group internal totp_secrets_dg records | grep enrolltest
   ```

**Expected Results:**

| Step | Expected |
|------|----------|
| Login | Successful authentication |
| QR code | Displays correctly |
| Authenticator | Account added |
| Confirmation | Code accepted |
| API check | `{"enrolled":true}` |
| Data group | User entry exists |

### Test 3.2: Enrolled User MFA Login Flow

**Objective:** Verify complete MFA login flow for enrolled user.

**Steps:**

1. **Access MFA portal:**
   ```
   https://portal.mfa-demo.local
   ```

2. **Enter primary credentials:**
   - Username: `enrolltest`
   - Password: `EnrollP@ss123!`

3. **Verify TOTP page displays:**
   - Username shown (read-only)
   - TOTP code field displayed

4. **Enter TOTP code:**
   - Get current code from authenticator app
   - Enter code

5. **Verify access granted:**
   - Webtop displays
   - "Reset Authenticator" link visible
   - "TOTP Admin" link visible (if configured)

**Expected Results:**

| Step | Expected |
|------|----------|
| Primary auth | Successful |
| TOTP page | Displays code entry field |
| TOTP validation | Code accepted |
| Webtop | Access granted, links visible |

### Test 3.3: Invalid TOTP Code

**Objective:** Verify invalid codes are rejected correctly.

**Steps:**

1. **Login to MFA portal with valid credentials**

2. **Enter invalid TOTP code:** `000000`

3. **Verify rejection:**
   - Access denied
   - Error message displayed

4. **Check rate limit increment:**
   ```bash
   curl -sk -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/status?username=enrolltest"
   ```

**Expected Results:**

| Test | Expected |
|------|----------|
| Invalid code | Access denied |
| Rate status | attempts > 0 |

### Test 3.4: Rate Limiting

**Objective:** Verify rate limiting functions correctly.

**Steps:**

1. **Submit multiple invalid codes:**
   ```bash
   for i in {1..6}; do
       curl -sk -H "X-API-Key: $API_KEY" \
           "https://totp-api.mfa-demo.local:443/api/v1/verify?username=enrolltest&code=000000"
       echo ""
   done
   ```

2. **Verify rate limited:**
   ```bash
   curl -sk -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/status?username=enrolltest"
   ```

3. **Attempt valid code (should fail):**
   ```bash
   # Even valid code should be rejected while rate limited
   curl -sk -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/verify?username=enrolltest&code=VALID_CODE"
   ```

4. **Reset rate limit:**
   ```bash
   curl -sk -X POST -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/rate-reset?username=enrolltest"
   ```

5. **Verify rate limit cleared:**
   ```bash
   curl -sk -H "X-API-Key: $API_KEY" \
       "https://totp-api.mfa-demo.local:443/api/v1/status?username=enrolltest"
   ```

**Expected Results:**

| Test | Expected |
|------|----------|
| After max attempts | `{"error":"rate_limited",...}` |
| Status while blocked | `{"blocked":true,...}` |
| Valid code while blocked | Still rejected |
| After reset | `{"attempts":0,"blocked":false,...}` |

### Test 3.5: Re-Enrollment Flow

**Objective:** Verify enrolled user can re-enroll with new authenticator.

**Steps:**

1. **Login to MFA portal successfully**

2. **Click "Reset Authenticator" on webtop**

3. **Complete re-enrollment:**
   - New QR code displayed
   - Scan with authenticator
   - Confirm with new code

4. **Verify old codes no longer work:**
   - Try code from old authenticator entry
   - Should be rejected

5. **Verify new codes work:**
   - Login to MFA portal
   - Use code from new authenticator entry
   - Should be accepted

**Expected Results:**

| Test | Expected |
|------|----------|
| Re-enrollment | New QR code displayed |
| Old code | Rejected |
| New code | Accepted |

### Test 3.6: Unenrolled User Redirect

**Objective:** Verify unenrolled users are redirected to enrollment.

**Steps:**

1. **Create new user (not enrolled):**
   ```bash
   ldbutil --add --instance="/Common/mfa_users_db" \
       --uname="newuser" --password="NewP@ss123!" \
       --first_name="New" --last_name="User" \
       --email="newuser@mfa-demo.local" \
       --user_groups="mfaUsers" --change_passwd="0" \
       --login_failures="0" --locked_out="0"
   ```

2. **Access MFA portal:**
   ```
   https://portal.mfa-demo.local
   ```

3. **Login with new user credentials:**
   - Username: `newuser`
   - Password: `NewP@ss123!`

4. **Verify redirect to enrollment:**
   - Should redirect to enrollment page
   - Not to TOTP code entry

**Expected Results:**

| Test | Expected |
|------|----------|
| Unenrolled user login | Redirect to enrollment |
| URL after redirect | https://totp-enroll.mfa-demo.local/enroll |

### Test 3.7: Admin UI Functions

**Objective:** Verify Admin UI functionality.

**Steps:**

1. **Access Admin UI:**
   ```
   https://totp-admin.mfa-demo.local/
   ```

2. **Verify dashboard loads:**
   - User count displayed
   - System status shown

3. **View user list:**
   - Enrolled users displayed
   - User details accessible

4. **Test rate limit reset:**
   - Select user
   - Reset rate limit
   - Verify reset via API

5. **Test user unenroll:**
   - Select test user
   - Unenroll
   - Verify via API:
     ```bash
     curl -sk -H "X-API-Key: $API_KEY" \
         "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"
     ```

**Expected Results:**

| Test | Expected |
|------|----------|
| Dashboard | Loads correctly |
| User list | Shows enrolled users |
| Rate reset | Clears user rate limit |
| Unenroll | Removes user enrollment |

---

## Phase 4: Production Readiness Testing

### Test 4.1: Load Testing

**Objective:** Verify system handles expected load.

**Simple Load Test Script:**

```bash
#!/bin/bash
# load_test.sh - Simple concurrent request test

API_KEY="your-api-key-here"
CONCURRENT=10
REQUESTS=100

echo "Starting load test: $REQUESTS requests, $CONCURRENT concurrent"

for i in $(seq 1 $REQUESTS); do
    curl -sk -H "X-API-Key: $API_KEY" \
        "https://totp-api.mfa-demo.local:443/api/v1/health" &
    
    # Limit concurrent requests
    if [ $((i % CONCURRENT)) -eq 0 ]; then
        wait
    fi
done

wait
echo "Load test complete"
```

**Expected Results:**

| Metric | Expected |
|--------|----------|
| Response time | < 100ms average |
| Error rate | 0% |
| CPU impact | < 50% increase |

### Test 4.2: Failover Testing (HA Only)

**Objective:** Verify seamless failover.

**Steps:**

1. **Verify current active unit:**
   ```bash
   tmsh show cm traffic-group traffic-group-1
   ```

2. **Initiate failover:**
   ```bash
   tmsh run sys failover standby
   ```

3. **Verify failover complete:**
   ```bash
   tmsh show cm traffic-group traffic-group-1
   ```

4. **Test user authentication:**
   - Login to MFA portal
   - Complete MFA
   - Verify access granted

5. **Test new enrollment:**
   - Create new user
   - Complete enrollment
   - Verify persistence

6. **Verify data sync:**
   ```bash
   # On new standby (old active)
   tmsh list ltm data-group internal totp_secrets_dg records | grep newuser
   ```

7. **Fail back:**
   ```bash
   tmsh run sys failover standby
   ```

**Expected Results:**

| Test | Expected |
|------|----------|
| Failover time | < 30 seconds |
| Authentication | Works on new active |
| Enrollment | Persists correctly |
| Data sync | New enrollments sync to standby |

### Test 4.3: Recovery Testing

**Objective:** Verify system recovers from failures.

**Test 4.3.1: TMM Restart Recovery**

```bash
# Restart TMM
bigstart restart tmm

# Wait for recovery
sleep 60

# Test API
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"

# Test user authentication
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=enrolltest"
```

**Test 4.3.2: Alert Daemon Recovery**

```bash
# Stop alertd
bigstart stop alertd

# Attempt enrollment (should work, but not persist)
# ...

# Restart alertd
bigstart start alertd

# Verify alert system
logger -p local0.alert "TOTP_ENROLL_TRIGGER:recoverytest"
sleep 3
grep "recoverytest" /var/log/ltm | tail -3
```

**Expected Results:**

| Test | Expected |
|------|----------|
| After TMM restart | API responds, users can authenticate |
| After alertd restart | Alerts trigger correctly |

### Test 4.4: Security Testing

**Objective:** Verify security controls function correctly.

**Test 4.4.1: API Key Enforcement**

```bash
# All endpoints should require API key
for endpoint in health check verify status rate-summary; do
    echo "Testing /api/v1/$endpoint without key:"
    curl -sk "https://totp-api.mfa-demo.local:443/api/v1/$endpoint?username=test"
    echo ""
done
```

**Test 4.4.2: Rate Limit Bypass Attempt**

```bash
# Attempt to bypass rate limit by varying parameters
for i in {1..10}; do
    curl -sk -H "X-API-Key: $API_KEY" \
        "https://totp-api.mfa-demo.local:443/api/v1/verify?username=testuser&code=00000$i"
done

# Check if rate limited
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"
```

**Test 4.4.3: Input Validation**

```bash
# Test with special characters
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=test%27%3B--"

# Test with long input
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=$(python -c 'print("a"*1000)')"
```

**Expected Results:**

| Test | Expected |
|------|----------|
| No API key | 401 Unauthorized |
| Rate limit bypass | Not possible |
| Special characters | Handled safely |
| Long input | Handled safely |

---

## Test Matrix

### Enrollment Tests

| Test ID | Description | Prerequisites | Expected Result | Status |
|---------|-------------|---------------|-----------------|--------|
| E-01 | New user enrollment | User in auth backend | QR code displays, enrollment succeeds | |
| E-02 | Enrollment confirmation | E-01 complete | Valid code confirms enrollment | |
| E-03 | Enrollment persistence | E-02 complete | User in data group after ~5s | |
| E-04 | Enrollment rate limit | None | Blocked after max attempts | |
| E-05 | Re-enrollment | User enrolled | New secret replaces old | |
| E-06 | Duplicate enrollment | User enrolled | Re-enrollment flow triggered | |

### Authentication Tests

| Test ID | Description | Prerequisites | Expected Result | Status |
|---------|-------------|---------------|-----------------|--------|
| A-01 | Valid credentials + valid TOTP | User enrolled | Access granted | |
| A-02 | Valid credentials + invalid TOTP | User enrolled | Access denied | |
| A-03 | Invalid credentials | User exists | Access denied (before TOTP) | |
| A-04 | Non-existent user | None | Access denied | |
| A-05 | Unenrolled user | User in auth backend | Redirect to enrollment | |
| A-06 | Rate limited user | User rate limited | Access denied with retry_after | |
| A-07 | Expired TOTP code | User enrolled | Code rejected | |

### API Tests

| Test ID | Description | Prerequisites | Expected Result | Status |
|---------|-------------|---------------|-----------------|--------|
| API-01 | Health endpoint | None | `{"status":"ok"}` | |
| API-02 | Check enrolled user | User enrolled | `{"enrolled":true}` | |
| API-03 | Check unenrolled user | User not enrolled | `{"enrolled":false}` | |
| API-04 | Verify valid code | User enrolled | `{"success":true}` | |
| API-05 | Verify invalid code | User enrolled | `{"success":false}` | |
| API-06 | Rate status | None | Status object returned | |
| API-07 | Rate reset | User rate limited | Rate limit cleared | |
| API-08 | Bulk rate reset | Users rate limited | All rate limits cleared | |
| API-09 | Invalid API key | None | 401 Unauthorized | |
| API-10 | Missing API key | None | 401 Unauthorized | |

### Admin UI Tests

| Test ID | Description | Prerequisites | Expected Result | Status |
|---------|-------------|---------------|-----------------|--------|
| ADM-01 | Dashboard loads | None | Dashboard displays | |
| ADM-02 | User list displays | Users enrolled | Users listed | |
| ADM-03 | User details view | User enrolled | Details displayed | |
| ADM-04 | Rate limit reset | User rate limited | Rate limit cleared | |
| ADM-05 | User unenroll | User enrolled | User unenrolled | |
| ADM-06 | Bulk operations | Multiple users | Operations succeed | |

### HA Tests

| Test ID | Description | Prerequisites | Expected Result | Status |
|---------|-------------|---------------|-----------------|--------|
| HA-01 | Config sync | HA configured | Data groups synced | |
| HA-02 | Failover - auth works | HA configured | Auth works on new active | |
| HA-03 | Failover - enrollment | HA configured | Enrollment works, persists | |
| HA-04 | Fail back | HA configured | Services work on original | |
| HA-05 | Alert scripts both units | HA configured | Scripts present on both | |

---

## Automated Test Script

### Smoke Test Script

```bash
#!/bin/bash
#
# totp_smoke_test.sh - Quick validation of TOTP MFA solution
#

set -e

# Configuration
API_HOST="totp-api.mfa-demo.local"
API_PORT="443"
INTERNAL_API="10.255.255.255:80"
PORTAL_HOST="portal.mfa-demo.local"
ENROLL_HOST="totp-enroll.mfa-demo.local"
ADMIN_HOST="totp-admin.mfa-demo.local"

# Get API key
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

if [ -z "$API_KEY" ]; then
    echo "ERROR: Failed to retrieve API key"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

# Test function
run_test() {
    local name="$1"
    local cmd="$2"
    local expected="$3"
    
    echo -n "Testing: $name ... "
    
    result=$(eval "$cmd" 2>/dev/null)
    
    if echo "$result" | grep -q "$expected"; then
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((FAILED++))
    fi
}

# Warning function
run_warning_test() {
    local name="$1"
    local cmd="$2"
    local expected="$3"
    
    echo -n "Testing: $name ... "
    
    result=$(eval "$cmd" 2>/dev/null)
    
    if echo "$result" | grep -q "$expected"; then
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}WARNING${NC}"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((WARNINGS++))
    fi
}

echo "========================================"
echo "  TOTP MFA Solution - Smoke Test"
echo "========================================"
echo ""

echo "--- Infrastructure Tests ---"
run_test "NTP Sync" "ntpq -p | grep -c '^\*'" "1"
run_test "External API Reachable" "curl -sk -o /dev/null -w '%{http_code}' -H 'X-API-Key: $API_KEY' 'https://$API_HOST:$API_PORT/api/v1/health'" "200"
run_test "Internal API Reachable" "curl -s -o /dev/null -w '%{http_code}' -H 'X-API-Key: $API_KEY' 'http://$INTERNAL_API/api/v1/health'" "200"
run_test "Alert Daemon Running" "bigstart status alertd | grep -c 'run'" "1"

echo ""
echo "--- API Tests ---"
run_test "API Health" "curl -sk -H 'X-API-Key: $API_KEY' 'https://$API_HOST:$API_PORT/api/v1/health'" '"status":"ok"'
run_test "API Auth Required" "curl -sk 'https://$API_HOST:$API_PORT/api/v1/health'" 'unauthorized'
run_test "Rate Summary" "curl -sk -H 'X-API-Key: $API_KEY' 'https://$API_HOST:$API_PORT/api/v1/rate-summary'" '"verify"'

echo ""
echo "--- Virtual Server Tests ---"
run_test "Enrollment VS" "tmsh show ltm virtual vs_totp_enroll | grep -c 'available'" "1"
run_test "API VS" "tmsh show ltm virtual vs_totp_api | grep -c 'available'" "1"
run_test "Internal API VS" "tmsh show ltm virtual vs_totp_api_internal | grep -c 'available'" "1"
run_test "Portal VS" "tmsh show ltm virtual vs_mfa_portal | grep -c 'available'" "1"
run_test "Admin VS" "tmsh show ltm virtual vs_totp_admin | grep -c 'available'" "1"

echo ""
echo "--- Data Group Tests ---"
run_test "Config DG Exists" "tmsh list ltm data-group internal totp_config_dg | grep -c 'totp_config_dg'" "1"
run_test "Secrets DG Exists" "tmsh list ltm data-group internal totp_secrets_dg | grep -c 'totp_secrets_dg'" "1"
run_test "Encryption Key Set" "tmsh list ltm data-group internal totp_config_dg records | grep -c 'encryption_key'" "1"

echo ""
echo "--- Access Policy Tests ---"
run_test "Enrollment AP Applied" "tmsh show apm profile access ap_totp_enroll | grep -c 'applied'" "1"
run_test "Portal AP Applied" "tmsh show apm profile access ap_mfa_portal | grep -c 'applied'" "1"

echo ""
echo "========================================"
echo "  Test Results"
echo "========================================"
echo -e "  Passed:   ${GREEN}$PASSED${NC}"
echo -e "  Failed:   ${RED}$FAILED${NC}"
echo -e "  Warnings: ${YELLOW}$WARNINGS${NC}"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0
```

### Save and Run Smoke Test

```bash
# Save script
cat > /config/totp/smoke_test.sh << 'SCRIPT'
# (paste script content here)
SCRIPT

chmod +x /config/totp/smoke_test.sh

# Run smoke test
/config/totp/smoke_test.sh
```

---

## Troubleshooting Test Failures

### Common Issues

| Symptom | Possible Cause | Resolution |
|---------|----------------|------------|
| API returns 401 | Invalid/missing API key | Verify API key in totp_config_dg |
| TOTP codes always fail | NTP out of sync | Check `ntpq -p`, fix NTP |
| Enrollment not persisting | alertd not running | `bigstart restart alertd` |
| Redirect not working | Access policy not applied | Apply policy in VPE |
| QR code not displaying | iFile not created | Verify qrcode_js iFile |
| Rate limit not resetting | Wrong API endpoint | Use correct reset endpoint |

### Debug Commands

```bash
# Enable APM debug logging
tmsh modify sys db log.access.level value debug
tail -f /var/log/apm

# Watch iRule execution
tail -f /var/log/ltm | grep -iE "totp|mfa|error"

# Check subtable contents
tmsh show ltm rule irule_totp_shared stats

# Disable debug logging
tmsh modify sys db log.access.level value warning
```

---

## Save Configuration

```bash
tmsh save sys config
```

---

## Test Summary Checklist

### Pre-Production Checklist

- [ ] All Phase 1 tests passed
- [ ] All Phase 2 tests passed
- [ ] All Phase 3 tests passed
- [ ] All Phase 4 tests passed
- [ ] Smoke test script runs successfully
- [ ] HA failover tested (if applicable)
- [ ] Recovery procedures tested
- [ ] Load testing completed
- [ ] Security testing completed
- [ ] Documentation reviewed

### Go-Live Checklist

- [ ] All test users removed or passwords changed
- [ ] Debug logging disabled
- [ ] Rate limits set to production values
- [ ] Admin UI access restricted
- [ ] Backup procedures verified
- [ ] Monitoring configured
- [ ] Runbook prepared
- [ ] Support team trained

---

## Next Steps

Testing complete. Refer to:

- [Administration](10-administration.md) for operational procedures
- [Troubleshooting](appendicies/log-reference.md) for log analysis
- [API Reference](appendicies/api-reference.md) for endpoint details