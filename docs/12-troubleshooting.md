
# Troubleshooting

## TOTP Codes Fail

| Cause | Fix |
|---|---|
| NTP skew | `ntpdate -u pool.ntp.org` |
| Encryption key mismatch (HA) | Re-sync config |
| Narrow time window | Add `totp_window` = `2` to `totp_config_dg` |
| One user only | Unenroll + re-enroll |

## HTTP Auth Agent

| Symptom | Fix |
|---|---|
| Always Failure | Check: Start URI, Form Action, API key, success match, VS status, iRule order |
| Intermittent | Check rate limiting via Admin UI or API `/api/v1/status` |

## Enrollment

| Symptom | Fix |
|---|---|
| QR missing | Check iFile: `tmsh list ltm ifile qrcode_js` |
| Not enrolled after enroll | Check logs: `grep "totp-enroll" /var/log/ltm` |
| Rate limited | Use Admin UI to reset user |

## Alert Scripts

| Symptom | Fix |
|---|---|
| DG not updated after enroll | Check `user_alert.conf` syntax + script permissions |
| Unenroll not removing from DG | Check `totp_unenroll.sh` permissions and log output |

## Diagnostics

```bash
ntpq -p; date -u
tail -f /var/log/ltm | grep -E "TOTP|MFA|totp"
tail -f /var/log/ltm | grep LOCKOUT

# APM debug (revert when done!)
tmsh modify sys db log.access.level value debug
tail -f /var/log/apm
tmsh modify sys db log.access.level value notice