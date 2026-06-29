# API Endpoint Reference

All endpoints require the `X-API-Key` header. The key is stored in `totp_config_dg`.

## Endpoints

| Method | Path | Rate Limited | Purpose |
|---|---|---|---|
| GET | `/api/v1/health` | No | Health check |
| GET | `/api/v1/check?username=…` | No | Enrollment status |
| GET/POST | `/api/v1/verify` | **Yes** | Verify TOTP code |
| GET | `/api/v1/status?username=…` | No | Verification rate status |
| GET | `/api/v1/enroll-status?username=…` | No | Enrollment rate status |
| GET | `/api/v1/rate-summary` | No | All rate limits overview |
| POST | `/api/v1/rate-reset?username=…` | No | Reset verify (1 user) |
| POST | `/api/v1/enroll-rate-reset?username=…` | No | Reset enroll (1 user) |
| POST | `/api/v1/rate-reset-all` | No | Clear ALL limits |
| POST | `/api/v1/rate-reset-verify-all` | No | Clear verify limits |
| POST | `/api/v1/rate-reset-enroll-all` | No | Clear enroll limits |
| POST | `/api/v1/populate-table` | No | Reload table from DG |
| GET | `/api/v1/export-secret?username=…` | No | Get cached secret (internal) |

## Response Codes

| Code | Meaning |
|---|---|
| 200 | Success |
| 400 | Bad request |
| 401 | Authentication failure |
| 403 | Forbidden (invalid API key) |
| 404 | Not found |
| 429 | Rate limited (includes `Retry-After` header) |
| 500 | Internal error |

## Example Usage

```bash
API_KEY="your_api_key"

# Health check
curl -s -H "X-API-Key: $API_KEY" http://10.255.255.255/api/v1/health

# Check enrollment
curl -s -H "X-API-Key: $API_KEY" "http://10.255.255.255/api/v1/check?username=testuser"

# Verify code (form-encoded, mimics APM HTTP Auth)
curl -s -X POST -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=testuser&code=123456" \
    http://10.255.255.255/api/v1/verify

# Rate limit summary
curl -s -H "X-API-Key: $API_KEY" http://10.255.255.255/api/v1/rate-summary

# Bulk reset
curl -s -X POST -H "X-API-Key: $API_KEY" http://10.255.255.255/api/v1/rate-reset-all