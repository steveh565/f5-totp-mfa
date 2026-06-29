# Object Inventory

## Virtual Servers

| Name | Destination | SSL | iRules | Profile |
|---|---|---|---|---|
| `vs_totp_enroll` | 10.1.1.100:443 | Y | shared, enroll | `ap_totp_enroll` |
| `vs_totp_verify` | 10.1.1.101:443 | Y | shared, verify | — |
| `vs_totp_verify_internal` | 10.255.255.255:80 | N | shared, verify | — |
| `vs_mfa_portal` | 10.1.1.102:443 | Y | shared, idp_mfa | `ap_mfa_portal` |
| `vs_totp_admin` | 10.1.1.104:443 | Y | shared, admin_ui | — |

## iRules

| Name | Purpose |
|---|---|
| `irule_totp_shared` | Shared: crypto, TOTP, rate limiting, branding |
| `irule_totp_enroll` | Enrollment + re-enrollment |
| `irule_totp_verify` | Verification API + admin endpoints |
| `irule_idp_mfa` | MFA enrollment check |
| `irule_totp_admin_ui` | Admin web UI |

## Data Groups

| Name | Type | Purpose |
|---|---|---|
| `totp_secrets_dg` | Internal string | Encrypted TOTP secrets (persistence + HA sync) |
| `totp_config_dg` | Internal string | API key, encryption key, issuer, rate limits |

## Subtables

| Name | Purpose |
|---|---|
| `totp_users` | Runtime user secrets (primary read source) |
| `totp_ratelimit` | Verification rate limit counters |
| `totp_enroll_ratelimit` | Enrollment rate limit + IP counters |

## Filesystem

| Path | Purpose |
|---|---|
| `/config/totp/totp_enroll.sh` | Commits secrets to data group |
| `/config/totp/totp_unenroll.sh` | Removes secrets from data group |
| `/config/user_alert.conf` | Alert triggers |

## Session Variables

| Variable | Purpose |
|---|---|
| `session.custom.totp.enroll_secret` | Temp secret during enrollment |
| `session.custom.totp.code` | User-entered TOTP code |
| `session.custom.totp.enrolled` | Enrollment check result |
| `session.custom.totp.attempts` | Retry macro counter |
| `session.custom.totp.max_attempts` | Max attempts display |
| `session.custom.totp.reenroll_step` | Re-enrollment step tracker |
| `session.custom.totp.reenroll_verified` | Current TOTP verified flag |
| `session.custom.totp.reenroll_new_secret` | Temp new secret |