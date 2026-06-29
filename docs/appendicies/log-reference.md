# Log Message Reference

| Pattern | Level | Meaning |
|---|---|---|
| `TOTP_ENROLL_TRIGGER:<user>` | alert | Triggers DG enrollment commit |
| `TOTP_UNENROLL_TRIGGER:<user>` | alert | Triggers DG unenrollment |
| `totp-enroll: Committed secret` | info | DG commit success |
| `totp-unenroll: Removed` | info | DG removal success |
| `TOTP_RATE:ATTEMPT:…` | info/warn | Verification attempt |
| `TOTP_RATE:BLOCKED:…` | warn | Verification rejected |
| `TOTP_RATE:LOCKOUT:…` | alert | Verification max reached |
| `TOTP_RATE:RESET:…` | info | Counter cleared |
| `TOTP_RATE:BULK_RESET:…` | notice | All verify limits cleared |
| `TOTP_ENROLL_RATE:ATTEMPT:…` | info | Enrollment attempt |
| `TOTP_ENROLL_RATE:BLOCKED:…` | warn | Enrollment rejected |
| `TOTP_ENROLL_RATE:LOCKOUT:…` | alert | Enrollment max reached |
| `TOTP_ENROLL_RATE:IP_BLOCKED:…` | warn | IP throttled |
| `TOTP_ENROLL_RATE:IP_LOCKOUT:…` | alert | IP max reached |
| `MFA\|<sid>:…` | info | MFA portal enrollment check |
| `TOTP RULE_INIT:…` | info | Subtable populated from DG |