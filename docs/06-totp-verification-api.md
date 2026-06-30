# 06 - TOTP Verification API

This section covers the TOTP verification API infrastructure including the API iRule, virtual servers (external and internal), rate limiting, and API endpoint reference.

---

## API Architecture Overview

The verification API provides a centralized endpoint for TOTP code validation and user management. Two virtual servers expose the API:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        API Architecture                                     │
└─────────────────────────────────────────────────────────────────────────────┘

                    External Clients                    APM HTTP Auth Agent
                          │                                     │
                          │ HTTPS (443)                         │ HTTP (80)
                          ▼                                     ▼
              ┌─────────────────────┐              ┌─────────────────────────┐
              │   vs_totp_api       │              │  vs_totp_api_internal   │
              │   10.1.1.101:443    │              │  10.255.255.255:80      │
              │   (External)        │              │  (Non-routable)         │
              └─────────────────────┘              └─────────────────────────┘
                          │                                     │
                          │                                     │
                          ▼                                     ▼
              ┌───────────────────────────────────────────────────────────────┐
              │                    irule_totp_api                             │
              │                                                               │
              │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
              │  │ /api/v1/    │  │ /api/v1/    │  │ /api/v1/            │   │
              │  │ verify      │  │ check       │  │ rate-reset          │   │
              │  └─────────────┘  └─────────────┘  └─────────────────────┘   │
              │                                                               │
              └───────────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────────────────────────────────────────────┐
              │                   irule_totp_shared                           │
              │                                                               │
              │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
              │  │ verify_totp │  │ decrypt_    │  │ Rate limit          │   │
              │  │             │  │ secret      │  │ management          │   │
              │  └─────────────┘  └─────────────┘  └─────────────────────┘   │
              │                                                               │
              └───────────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────────────────────────────────────────────┐
              │                    Data Storage                               │
              │                                                               │
              │  ┌─────────────────┐          ┌─────────────────────────┐    │
              │  │ totp_users      │          │ totp_ratelimit          │    │
              │  │ subtable        │          │ subtable                │    │
              │  │ (secrets)       │          │ (attempt counts)        │    │
              │  └─────────────────┘          └─────────────────────────┘    │
              │                                                               │
              └───────────────────────────────────────────────────────────────┘
```

### Virtual Server Comparison

| Aspect | vs_totp_api (External) | vs_totp_api_internal |
|--------|------------------------|----------------------|
| IP Address | 10.1.1.101 | 10.255.255.255 |
| Port | 443 (HTTPS) | 80 (HTTP) |
| SSL | Yes (mfa-clientssl) | No |
| Accessible From | Network clients | BIG-IP only |
| Primary Use | Admin tools, external apps | APM HTTP Auth agent |
| FQDN | totp-api.mfa-demo.local | (none - internal only) |

---

## API Authentication

All API endpoints require authentication via the `X-API-Key` header.

### API Key Storage

The API key is stored in `totp_config_dg`:

```bash
# View current API key
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key"
```

### API Key Rotation

To rotate the API key:

```bash
# Generate new key
NEW_API_KEY=$(openssl rand -hex 32)
echo "New API Key: $NEW_API_KEY"

# Update data group
tmsh modify ltm data-group internal totp_config_dg records modify {
    api_key { data "$NEW_API_KEY" }
}

# Save configuration
tmsh save sys config
```

> **Important:** After rotating the API key, update:
> - Alert scripts (`/config/totp/totp_enroll.sh`)
> - Any external applications using the API
> - Admin UI configurations (if applicable)

### Authentication Failure Response

Requests without a valid API key receive:

```json
{"error":"unauthorized","message":"Invalid or missing API key"}
```

HTTP Status: `401 Unauthorized`

---

## API iRule

### irule_totp_api

The API iRule handles all verification and management endpoints.

**Key responsibilities:**

| Function | Description |
|----------|-------------|
| API key validation | Authenticate all requests |
| TOTP verification | Validate codes against stored secrets |
| Rate limit enforcement | Track and enforce attempt limits |
| User management | Check enrollment status, export secrets |
| Rate limit management | Reset counters for users |

Create via GUI: **Local Traffic → iRules → iRule List → Create**

- Name: `irule_totp_api`
- Definition: (paste content from `irules/irule_totp_api.tcl`)

### Verify iRule

```bash
tmsh list ltm rule irule_totp_api
```

---

## HTTP Profile

Create a dedicated HTTP profile for the API virtual servers:

```bash
tmsh create ltm profile http http_totp_api defaults-from http
```

---

## Virtual Servers

### External API Virtual Server

The external API VS provides HTTPS access for administrative tools and external applications:

```bash
tmsh create ltm virtual vs_totp_api {
    destination 10.1.1.101:443
    ip-protocol tcp
    profiles replace-all-with {
        mfa-clientssl { context clientside }
        http_totp_api
        tcp
    }
    source-address-translation { type automap }
    rules { irule_totp_shared irule_totp_api }
}
```

### Internal API Virtual Server

The internal API VS provides HTTP access for the APM HTTP Auth agent:

```bash
tmsh create ltm virtual vs_totp_api_internal {
    destination 10.255.255.255:80
    ip-protocol tcp
    profiles replace-all-with {
        http_totp_api
        tcp
    }
    source-address-translation { type automap }
    rules { irule_totp_shared irule_totp_api }
}
```

> **Note:** The internal VS uses HTTP (no SSL) because:
> - Traffic never leaves the BIG-IP
> - APM HTTP Auth agent connects locally
> - Reduces processing overhead
> - Non-routable IP prevents external access

### Verify Virtual Servers

```bash
# List both API virtual servers
tmsh list ltm virtual vs_totp_api
tmsh list ltm virtual vs_totp_api_internal
```

---

## API Endpoint Reference

All endpoints require the `X-API-Key` header unless otherwise noted.

### Health Check

**Endpoint:** `GET /api/v1/health`

**Rate Limited:** No

**Purpose:** Verify API availability

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

**Response:**
```json
{"status":"ok"}
```

---

### Enrollment Check

**Endpoint:** `GET /api/v1/check?username=<username>`

**Rate Limited:** No

**Purpose:** Check if user is enrolled for TOTP

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"
```

**Response (enrolled):**
```json
{"enrolled":true,"username":"testuser"}
```

**Response (not enrolled):**
```json
{"enrolled":false,"username":"testuser"}
```

---

### Verify TOTP Code

**Endpoint:** `GET|POST /api/v1/verify`

**Rate Limited:** Yes

**Purpose:** Validate TOTP code for user

**Request (GET):**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/verify?username=testuser&code=123456"
```

**Request (POST - form data):**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    -d "username=testuser&code=123456" \
    "https://totp-api.mfa-demo.local:443/api/v1/verify"
```

**Response (success):**
```json
{"success":true,"username":"testuser"}
```

**Response (invalid code):**
```json
{"success":false,"username":"testuser","error":"invalid_code"}
```

**Response (rate limited):**
```json
{"success":false,"username":"testuser","error":"rate_limited","retry_after":245}
```

**Response (user not enrolled):**
```json
{"success":false,"username":"testuser","error":"not_enrolled"}
```

---

### Verification Rate Status

**Endpoint:** `GET /api/v1/status?username=<username>`

**Rate Limited:** No

**Purpose:** Get verification rate limit status for user

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"
```

**Response:**
```json
{
    "username":"testuser",
    "attempts":2,
    "max_attempts":5,
    "window_seconds":300,
    "remaining":3,
    "blocked":false
}
```

**Response (blocked):**
```json
{
    "username":"testuser",
    "attempts":5,
    "max_attempts":5,
    "window_seconds":300,
    "remaining":0,
    "blocked":true,
    "retry_after":187
}
```

---

### Enrollment Rate Status

**Endpoint:** `GET /api/v1/enroll-status?username=<username>`

**Rate Limited:** No

**Purpose:** Get enrollment rate limit status for user

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-status?username=testuser"
```

**Response:**
```json
{
    "username":"testuser",
    "attempts":1,
    "max_attempts":3,
    "window_seconds":600,
    "remaining":2,
    "blocked":false
}
```

---

### Rate Limit Summary

**Endpoint:** `GET /api/v1/rate-summary`

**Rate Limited:** No

**Purpose:** Get overview of all rate-limited users

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-summary"
```

**Response:**
```json
{
    "verify":{
        "total_tracked":3,
        "blocked":1,
        "users":[
            {"username":"user1","attempts":2,"blocked":false},
            {"username":"user2","attempts":5,"blocked":true},
            {"username":"user3","attempts":1,"blocked":false}
        ]
    },
    "enroll":{
        "total_tracked":1,
        "blocked":0,
        "users":[
            {"username":"newuser","attempts":1,"blocked":false}
        ]
    }
}
```

---

### Reset Verification Rate Limit (Single User)

**Endpoint:** `POST /api/v1/rate-reset?username=<username>`

**Rate Limited:** No

**Purpose:** Reset verification rate limit for specific user

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset?username=testuser"
```

**Response:**
```json
{"success":true,"username":"testuser","message":"Rate limit reset"}
```

---

### Reset Enrollment Rate Limit (Single User)

**Endpoint:** `POST /api/v1/enroll-rate-reset?username=<username>`

**Rate Limited:** No

**Purpose:** Reset enrollment rate limit for specific user

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/enroll-rate-reset?username=testuser"
```

**Response:**
```json
{"success":true,"username":"testuser","message":"Enrollment rate limit reset"}
```

---

### Reset All Rate Limits

**Endpoint:** `POST /api/v1/rate-reset-all`

**Rate Limited:** No

**Purpose:** Clear all rate limits (verification and enrollment)

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-all"
```

**Response:**
```json
{"success":true,"message":"All rate limits cleared"}
```

---

### Reset All Verification Rate Limits

**Endpoint:** `POST /api/v1/rate-reset-verify-all`

**Rate Limited:** No

**Purpose:** Clear all verification rate limits only

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-verify-all"
```

**Response:**
```json
{"success":true,"message":"All verification rate limits cleared"}
```

---

### Reset All Enrollment Rate Limits

**Endpoint:** `POST /api/v1/rate-reset-enroll-all`

**Rate Limited:** No

**Purpose:** Clear all enrollment rate limits only

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset-enroll-all"
```

**Response:**
```json
{"success":true,"message":"All enrollment rate limits cleared"}
```

---

### Populate Table from Data Group

**Endpoint:** `POST /api/v1/populate-table`

**Rate Limited:** No

**Purpose:** Reload totp_users subtable from totp_secrets_dg (disaster recovery)

**Request:**
```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"
```

**Response:**
```json
{"success":true,"message":"Table populated","users_loaded":5}
```

---

### Export Secret (Internal Use)

**Endpoint:** `GET /api/v1/export-secret?username=<username>`

**Rate Limited:** No

**Purpose:** Retrieve encrypted secret for persistence (used by alert scripts)

**Request:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/export-secret?username=testuser"
```

**Response:**
```json
{"username":"testuser","secret":"<encrypted-base64-secret>"}
```

> **Note:** This endpoint returns the encrypted secret. It is used by the enrollment alert script to persist secrets to the data group.

---

## Rate Limiting

### Verification Rate Limiting

Protects against brute-force attacks on TOTP codes.

| Parameter | Default | Description |
|-----------|---------|-------------|
| rate_max_attempts | 5 | Maximum verification attempts |
| rate_window_seconds | 300 | Window duration (5 minutes) |

**Behavior:**

1. Each failed verification increments the attempt counter
2. Successful verification resets the counter
3. Counter exceeding `rate_max_attempts` blocks further attempts
4. Counter automatically expires after `rate_window_seconds`
5. Blocked users receive `rate_limited` error with `retry_after` seconds

### Enrollment Rate Limiting

Prevents enrollment abuse.

| Parameter | Default | Description |
|-----------|---------|-------------|
| enroll_rate_max_attempts | 3 | Maximum enrollment attempts |
| enroll_rate_window_seconds | 600 | Window duration (10 minutes) |

### Rate Limit Storage

Rate limits are stored in subtables:

| Subtable | Purpose | Key Format |
|----------|---------|------------|
| totp_ratelimit | Verification attempts | `<username>` |
| totp_enroll_ratelimit | Enrollment attempts | `<username>` |

### Modify Rate Limit Configuration

```bash
# Increase verification attempts
tmsh modify ltm data-group internal totp_config_dg records modify {
    rate_max_attempts { data "10" }
}

# Extend verification window to 10 minutes
tmsh modify ltm data-group internal totp_config_dg records modify {
    rate_window_seconds { data "600" }
}

# Increase enrollment attempts
tmsh modify ltm data-group internal totp_config_dg records modify {
    enroll_rate_max_attempts { data "5" }
}

tmsh save sys config
```

---

## Lazy Loading

The API implements lazy loading of secrets from the data group to the subtable.

### How Lazy Loading Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Lazy Loading Flow                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  API Request                Subtable                 Data Group
       │                        │                          │
       │ 1. Verify user         │                          │
       ├───────────────────────►│                          │
       │                        │                          │
       │ 2. Check subtable      │                          │
       │    for secret          │                          │
       │◄───────────────────────┤                          │
       │                        │                          │
       │ 3. Not found?          │                          │
       │    Query data group    │                          │
       ├───────────────────────────────────────────────────►│
       │                        │                          │
       │ 4. Secret found        │                          │
       │◄──────────────────────────────────────────────────┤
       │                        │                          │
       │ 5. Cache in subtable   │                          │
       ├───────────────────────►│                          │
       │                        │                          │
       │ 6. Proceed with        │                          │
       │    verification        │                          │
       │                        │                          │
```

### Benefits of Lazy Loading

| Benefit | Description |
|---------|-------------|
| Fast startup | No delay loading all users at TMM start |
| Memory efficient | Only active users loaded into subtable |
| HA compatible | Works with config-sync of data groups |
| Self-healing | Automatically reloads after TMM restart |

### Manual Table Population

For disaster recovery or testing, manually populate the subtable:

```bash
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"
```

---

## Testing the API

### Retrieve API Key

```bash
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records 2>/dev/null | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')
echo "API Key: $API_KEY"
```

### Test Health Endpoint

```bash
# External VS
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"

# Internal VS (from BIG-IP CLI)
curl -s -H "X-API-Key: $API_KEY" \
    "http://10.255.255.255:80/api/v1/health"
```

Expected: `{"status":"ok"}`

### Test Enrollment Check

```bash
# Check enrolled user
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"

# Check non-enrolled user
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=newuser"
```

### Test Verification

```bash
# Get current TOTP code from authenticator app, then:
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/verify?username=testuser&code=123456"
```

### Test Rate Limiting

```bash
# Submit multiple invalid codes to trigger rate limiting
for i in {1..6}; do
    curl -sk -H "X-API-Key: $API_KEY" \
        "https://totp-api.mfa-demo.local:443/api/v1/verify?username=testuser&code=000000"
    echo ""
done

# Check rate status
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/status?username=testuser"

# Reset rate limit
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset?username=testuser"
```

### Test Without API Key

```bash
# Should return 401 Unauthorized
curl -sk "https://totp-api.mfa-demo.local:443/api/v1/health"
```

---

## Troubleshooting

### API Returns 401 Unauthorized

```bash
# Verify API key is correct
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key"

# Ensure header is correct: X-API-Key (case-sensitive)
curl -sk -H "X-API-Key: $API_KEY" ...
```

### Verification Always Fails

```bash
# Check user is enrolled
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"

# Check NTP synchronization
ntpq -p

# Verify time_skew setting allows for drift
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "time_skew"
```

### Internal VS Not Responding

```bash
# Test from BIG-IP CLI
curl -s "http://10.255.255.255:80/api/v1/health"

# Check VS status
tmsh show ltm virtual vs_totp_api_internal

# Verify iRules attached
tmsh list ltm virtual vs_totp_api_internal rules
```

### Rate Limit Not Resetting

```bash
# Check subtable entries
tmsh show ltm rule irule_totp_shared stats

# Verify window_seconds configuration
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "rate_window"

# Force reset via API
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/rate-reset?username=testuser"
```

### Secrets Not Loading from Data Group

```bash
# Check data group has entries
tmsh list ltm data-group internal totp_secrets_dg records

# Force table population
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"

# Check for decryption errors in logs
tail -f /var/log/ltm | grep -i "decrypt\|totp"
```

---

## Log Messages

API-related log patterns (see [Log Reference](appendicies/log-reference.md)):

| Pattern | Meaning |
|---------|---------|
| `TOTP_RATE:ATTEMPT:<user>` | Verification attempt logged |
| `TOTP_RATE:BLOCKED:<user>` | Verification rejected (rate limited) |
| `TOTP_RATE:LOCKOUT:<user>` | Maximum attempts reached |
| `TOTP_RATE:RESET:<user>` | Rate limit reset for user |
| `TOTP_RATE:BULK_RESET` | All rate limits cleared |

---

## Security Considerations

### API Key Protection

- Store API key securely
- Rotate periodically (quarterly recommended)
- Use different keys for different environments
- Monitor for unauthorized API access

### Network Security

- External VS should be restricted by source IP if possible
- Internal VS uses non-routable IP by design
- Consider WAF policies for external VS
- Log and monitor API access

### Rate Limiting

- Tune rate limits based on expected usage
- Monitor for distributed attacks
- Consider IP-based rate limiting for additional protection

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
| API iRule | irule_totp_api |
| HTTP Profile | http_totp_api |
| External VS | vs_totp_api (10.1.1.101:443) |
| Internal VS | vs_totp_api_internal (10.255.255.255:80) |
| API Key | Stored in totp_config_dg |

### API Endpoint Summary

| Endpoint | Method | Rate Limited | Purpose |
|----------|--------|--------------|---------|
| /api/v1/health | GET | No | Health check |
| /api/v1/check | GET | No | Enrollment status |
| /api/v1/verify | GET/POST | Yes | Verify TOTP code |
| /api/v1/status | GET | No | Verification rate status |
| /api/v1/enroll-status | GET | No | Enrollment rate status |
| /api/v1/rate-summary | GET | No | All rate limits overview |
| /api/v1/rate-reset | POST | No | Reset verify (single user) |
| /api/v1/enroll-rate-reset | POST | No | Reset enroll (single user) |
| /api/v1/rate-reset-all | POST | No | Clear all limits |
| /api/v1/rate-reset-verify-all | POST | No | Clear verify limits |
| /api/v1/rate-reset-enroll-all | POST | No | Clear enroll limits |
| /api/v1/populate-table | POST | No | Reload table from DG |
| /api/v1/export-secret | GET | No | Get secret (internal) |

---

## Next Steps

Proceed to [07 - Persistence and HA](07-persistence-and-ha.md) to understand the data persistence architecture and high availability considerations.
