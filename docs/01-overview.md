# 01 - Overview

This section provides a comprehensive overview of the F5 BIG-IP APM TOTP MFA solution, including architecture, components, authentication flows, and design decisions.

---

## Solution Overview

The TOTP MFA solution provides time-based one-time password (TOTP) multi-factor authentication for F5 BIG-IP APM. It enables organizations to add a second authentication factor without requiring external MFA services or additional licensing costs.

### Key Features

| Feature | Description |
|---------|-------------|
| Self-contained | No external MFA services required |
| Standards-based | RFC 6238 TOTP compatible with any authenticator app |
| Self-service enrollment | Users enroll via QR code scanning |
| Self-service re-enrollment | Users can reset their authenticator |
| Rate limiting | Protection against brute-force attacks |
| Encrypted storage | AES-256 encryption for stored secrets |
| HA support | Config-sync compatible for high availability |
| Admin interface | Web-based administration console |
| API access | RESTful API for integration and management |

### Use Cases

| Use Case | Description |
|----------|-------------|
| VPN authentication | Add MFA to APM-based VPN access |
| Web application access | Protect internal web applications |
| Privileged access | Secure administrative portals |
| Compliance requirements | Meet MFA requirements for PCI-DSS, HIPAA, etc. |
| Zero-trust architecture | Additional verification layer |

---

## Architecture Overview

The solution consists of five virtual servers, five iRules, and supporting infrastructure:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Solution Architecture                                │
└─────────────────────────────────────────────────────────────────────────────┘

                                    Users
                                      │
                                      ▼
                    ┌─────────────────────────────────────┐
                    │           External Network          │
                    │              10.1.1.0/24            │
                    └─────────────────────────────────────┘
                                      │
        ┌─────────────┬───────────────┼───────────────┬─────────────┐
        │             │               │               │             │
        ▼             ▼               ▼               ▼             ▼
   ┌─────────┐   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ Enroll  │   │   API   │    │  Portal │    │  Admin  │    │   API   │
   │  :443   │   │  :443   │    │  :443   │    │  :443   │    │  :80    │
   │         │   │         │    │         │    │         │    │Internal │
   │10.1.1.  │   │10.1.1.  │    │10.1.1.  │    │10.1.1.  │    │10.255.  │
   │  100    │   │  101    │    │  102    │    │  104    │    │255.255  │
   └────┬────┘   └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
        │             │               │               │             │
        ▼             ▼               ▼               ▼             ▼
   ┌─────────┐   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ irule_  │   │ irule_  │    │ irule_  │    │ irule_  │    │ irule_  │
   │ totp_   │   │ totp_   │    │ idp_    │    │ totp_   │    │ totp_   │
   │ enroll  │   │ api     │    │ mfa     │    │admin_ui │    │ api     │
   └────┬────┘   └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
        │             │               │               │             │
        └─────────────┴───────────────┴───────────────┴─────────────┘
                                      │
                                      ▼
                         ┌───────────────────────┐
                         │   irule_totp_shared   │
                         │                       │
                         │  • TOTP generation    │
                         │  • Secret encryption  │
                         │  • Rate limiting      │
                         │  • Data access        │
                         └───────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
           ┌───────────────┐                   ┌───────────────┐
           │  Subtables    │                   │  Data Groups  │
           │  (Runtime)    │                   │  (Persistent) │
           │               │                   │               │
           │ • totp_users  │    ◄── sync ──►   │ • totp_       │
           │ • totp_       │                   │   secrets_dg  │
           │   ratelimit   │                   │ • totp_       │
           │ • totp_enroll │                   │   config_dg   │
           │   _ratelimit  │                   │               │
           └───────────────┘                   └───────────────┘
```

---

## Component Summary

### Virtual Servers

| Virtual Server | IP:Port | Purpose | Access |
|----------------|---------|---------|--------|
| vs_totp_enroll | 10.1.1.100:443 | TOTP enrollment | Users |
| vs_totp_api | 10.1.1.101:443 | External API access | Admins, Apps |
| vs_totp_api_internal | 10.255.255.255:80 | HTTP Auth agent | BIG-IP only |
| vs_mfa_portal | 10.1.1.102:443 | MFA login portal | Users |
| vs_totp_admin | 10.1.1.104:443 | Administration UI | Admins |

### iRules

| iRule | Purpose | Used By |
|-------|---------|---------|
| irule_totp_shared | Shared procedures (TOTP, crypto, rate limiting) | All VS |
| irule_totp_enroll | Enrollment page and processing | vs_totp_enroll |
| irule_totp_api | API endpoints | vs_totp_api, vs_totp_api_internal |
| irule_idp_mfa | MFA portal logic | vs_mfa_portal |
| irule_totp_admin_ui | Admin interface | vs_totp_admin |

### Data Storage

| Storage | Type | Purpose | Persistence |
|---------|------|---------|-------------|
| totp_users | Subtable | Runtime secret cache | Memory (TMM) |
| totp_ratelimit | Subtable | Verification rate counters | Memory (TMM) |
| totp_enroll_ratelimit | Subtable | Enrollment rate counters | Memory (TMM) |
| totp_secrets_dg | Data Group | Persistent secret storage | Config file |
| totp_config_dg | Data Group | Configuration parameters | Config file |

### Supporting Components

| Component | Purpose |
|-----------|---------|
| qrcode_js | iFile containing QR code JavaScript library |
| totp_enroll.sh | Alert script for enrollment persistence |
| totp_unenroll.sh | Alert script for unenrollment |
| user_alert.conf | Alert trigger configuration |
| mfa-clientssl | Client SSL profile for HTTPS |
| http_aaa_totp_verify | HTTP AAA for TOTP verification |
| ap_totp_enroll | Access profile for enrollment |
| ap_mfa_portal | Access profile for MFA portal |
| webtop_mfa | Webtop for authenticated users |

---

## Authentication Flows

### Flow 1: Initial Enrollment

New users must enroll before using TOTP authentication:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Initial Enrollment Flow                              │
└─────────────────────────────────────────────────────────────────────────────┘

  User              Portal           Enrollment VS         API            Storage
    │                  │                   │                │                │
    │ 1. Access        │                   │                │                │
    │    portal        │                   │                │                │
    ├─────────────────►│                   │                │                │
    │                  │                   │                │                │
    │ 2. Login         │                   │                │                │
    │    (user/pass)   │                   │                │                │
    ├─────────────────►│                   │                │                │
    │                  │                   │                │                │
    │                  │ 3. Check          │                │                │
    │                  │    enrollment     │                │                │
    │                  ├──────────────────────────────────►│                │
    │                  │                   │                │                │
    │                  │ 4. Not enrolled   │                │                │
    │                  │◄──────────────────────────────────┤                │
    │                  │                   │                │                │
    │ 5. Redirect to   │                   │                │                │
    │    enrollment    │                   │                │                │
    │◄─────────────────┤                   │                │                │
    │                  │                   │                │                │
    │ 6. Access        │                   │                │                │
    │    enrollment    │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │ 7. Login         │                   │                │                │
    │    (user/pass)   │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │ 8. QR code page  │                   │                │                │
    │◄─────────────────────────────────────┤                │                │
    │                  │                   │                │                │
    │ 9. Scan QR,      │                   │                │                │
    │    enter code    │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │                  │                   │ 10. Verify     │                │
    │                  │                   │     code       │                │
    │                  │                   ├───────────────►│                │
    │                  │                   │                │                │
    │                  │                   │ 11. Store      │                │
    │                  │                   │     secret     │                │
    │                  │                   ├───────────────────────────────►│
    │                  │                   │                │                │
    │ 12. Success,     │                   │                │                │
    │     redirect     │                   │                │                │
    │◄─────────────────────────────────────┤                │                │
    │                  │                   │                │                │
```

### Flow 2: MFA Authentication

Enrolled users authenticate with credentials plus TOTP:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MFA Authentication Flow                              │
└─────────────────────────────────────────────────────────────────────────────┘

  User              Portal            HTTP AAA          Internal API       Storage
    │                  │                  │                  │                │
    │ 1. Access        │                  │                  │                │
    │    portal        │                  │                  │                │
    ├─────────────────►│                  │                  │                │
    │                  │                  │                  │                │
    │ 2. Login page    │                  │                  │                │
    │◄─────────────────┤                  │                  │                │
    │                  │                  │                  │                │
    │ 3. Username +    │                  │                  │                │
    │    Password      │                  │                  │                │
    ├─────────────────►│                  │                  │                │
    │                  │                  │                  │                │
    │                  │ 4. Validate      │                  │                │
    │                  │    (LocalDB/AD)  │                  │                │
    │                  ├─────┐            │                  │                │
    │                  │◄────┘            │                  │                │
    │                  │                  │                  │                │
    │                  │ 5. Check         │                  │                │
    │                  │    enrolled      │                  │                │
    │                  ├──────────────────────────────────►│                │
    │                  │◄──────────────────────────────────┤                │
    │                  │                  │                  │                │
    │ 6. TOTP code     │                  │                  │                │
    │    page          │                  │                  │                │
    │◄─────────────────┤                  │                  │                │
    │                  │                  │                  │                │
    │ 7. Enter TOTP    │                  │                  │                │
    │    code          │                  │                  │                │
    ├─────────────────►│                  │                  │                │
    │                  │                  │                  │                │
    │                  │ 8. HTTP Auth     │                  │                │
    │                  ├─────────────────►│                  │                │
    │                  │                  │                  │                │
    │                  │                  │ 9. POST         │                │
    │                  │                  │    /api/v1/     │                │
    │                  │                  │    verify       │                │
    │                  │                  ├─────────────────►│                │
    │                  │                  │                  │                │
    │                  │                  │                  │ 10. Lookup    │
    │                  │                  │                  │     secret    │
    │                  │                  │                  ├───────────────►│
    │                  │                  │                  │◄───────────────┤
    │                  │                  │                  │                │
    │                  │                  │                  │ 11. Validate  │
    │                  │                  │                  │     TOTP      │
    │                  │                  │                  ├────┐          │
    │                  │                  │                  │◄───┘          │
    │                  │                  │                  │                │
    │                  │                  │ 12. Success     │                │
    │                  │                  │◄─────────────────┤                │
    │                  │                  │                  │                │
    │                  │ 13. Auth OK      │                  │                │
    │                  │◄─────────────────┤                  │                │
    │                  │                  │                  │                │
    │ 14. Webtop /     │                  │                  │                │
    │     Resources    │                  │                  │                │
    │◄─────────────────┤                  │                  │                │
    │                  │                  │                  │                │
```

### Flow 3: Re-Enrollment

Users can replace their authenticator via the webtop:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Re-Enrollment Flow                                   │
└─────────────────────────────────────────────────────────────────────────────┘

  User              Webtop           Enrollment VS         API            Storage
    │                  │                   │                │                │
    │ 1. Click "Reset  │                   │                │                │
    │    Authenticator"│                   │                │                │
    ├─────────────────►│                   │                │                │
    │                  │                   │                │                │
    │ 2. Redirect to   │                   │                │                │
    │    /reenroll     │                   │                │                │
    │◄─────────────────┤                   │                │                │
    │                  │                   │                │                │
    │ 3. Access        │                   │                │                │
    │    /reenroll     │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │ 4. Login         │                   │                │                │
    │    (user/pass)   │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │ 5. New QR code   │                   │                │                │
    │    (new secret)  │                   │                │                │
    │◄─────────────────────────────────────┤                │                │
    │                  │                   │                │                │
    │ 6. Scan new QR,  │                   │                │                │
    │    enter code    │                   │                │                │
    ├─────────────────────────────────────►│                │                │
    │                  │                   │                │                │
    │                  │                   │ 7. Replace     │                │
    │                  │                   │    secret      │                │
    │                  │                   ├───────────────────────────────►│
    │                  │                   │                │                │
    │ 8. Success       │                   │                │                │
    │◄─────────────────────────────────────┤                │                │
    │                  │                   │                │                │
```

---

## Data Flow

### Secret Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Secret Lifecycle                                     │
└─────────────────────────────────────────────────────────────────────────────┘

  1. GENERATION                2. STORAGE                 3. VERIFICATION
  ──────────────               ──────────                 ────────────────

  ┌─────────────┐          ┌─────────────────┐          ┌─────────────────┐
  │ Generate    │          │ Encrypt with    │          │ Decrypt secret  │
  │ random      │ ──────►  │ AES-256-ECB     │          │                 │
  │ Base32      │          │                 │          │                 │
  │ secret      │          │ Store in:       │          │ Generate        │
  │ (32 chars)  │          │ • Subtable      │  ──────► │ expected TOTP   │
  │             │          │ • Data Group    │          │                 │
  └─────────────┘          │   (via alert)   │          │ Compare with    │
                           │                 │          │ submitted code  │
                           └─────────────────┘          │                 │
                                                        │ Apply time skew │
                                                        │ tolerance       │
                                                        └─────────────────┘
```

### Persistence Mechanism

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Persistence Mechanism                                │
└─────────────────────────────────────────────────────────────────────────────┘

  Enrollment                 Alert System                    Data Group
  ──────────                 ────────────                    ──────────

  ┌─────────────┐          ┌─────────────────┐          ┌─────────────────┐
  │ Store in    │          │ Log trigger:    │          │ Script executes:│
  │ subtable    │ ──────►  │ TOTP_ENROLL_    │ ──────►  │ • Query API for │
  │             │          │ TRIGGER:user    │          │   secret        │
  │ Log trigger │          │                 │          │ • tmsh modify   │
  │ message     │          │ alertd matches  │          │   data-group    │
  │             │          │ pattern         │          │ • Save config   │
  └─────────────┘          │                 │          │                 │
                           │ Executes        │          │ Secret persists │
                           │ totp_enroll.sh  │          │ in bigip.conf   │
                           └─────────────────┘          └─────────────────┘
```

### Lazy Loading

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Lazy Loading Flow                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  Verification Request       Subtable Lookup              Data Group Lookup
  ────────────────────       ───────────────              ─────────────────

  ┌─────────────────┐       ┌─────────────────┐          ┌─────────────────┐
  │ Receive verify  │       │ Check subtable  │          │ Check data      │
  │ request for     │ ────► │ for user secret │          │ group for user  │
  │ username        │       │                 │          │                 │
  │                 │       │ Found?          │          │ Found?          │
  │                 │       │ ├─ Yes: Use it  │          │ ├─ Yes: Cache   │
  │                 │       │ │               │          │ │   in subtable │
  │                 │       │ └─ No: Continue │ ──────►  │ │   and use     │
  │                 │       │                 │          │ │               │
  │                 │       │                 │          │ └─ No: User not │
  │                 │       │                 │          │       enrolled  │
  └─────────────────┘       └─────────────────┘          └─────────────────┘
```

---

## Security Architecture

### Defense Layers

| Layer | Protection |
|-------|------------|
| Network | Non-routable internal API, source IP restrictions |
| Transport | TLS 1.2+ encryption, strong cipher suites |
| Authentication | API key for management endpoints |
| Rate Limiting | Per-user attempt counters with lockout |
| Storage | AES-256 encryption for secrets at rest |
| Logging | Audit trail for enrollments and verifications |

### Rate Limiting

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Rate Limiting                                        │
└─────────────────────────────────────────────────────────────────────────────┘

  Verification Rate Limiting              Enrollment Rate Limiting
  ──────────────────────────              ────────────────────────

  ┌─────────────────────────┐            ┌─────────────────────────┐
  │ Per-user tracking       │            │ Per-user tracking       │
  │                         │            │ Per-IP tracking         │
  │ Default: 5 attempts     │            │                         │
  │ Window: 300 seconds     │            │ Default: 3 attempts     │
  │                         │            │ Window: 600 seconds     │
  │ Failed attempt:         │            │                         │
  │ • Increment counter     │            │ Failed attempt:         │
  │ • Check threshold       │            │ • Increment counter     │
  │                         │            │ • Check threshold       │
  │ Threshold exceeded:     │            │                         │
  │ • Block further attempts│            │ Threshold exceeded:     │
  │ • Return retry_after    │            │ • Block further attempts│
  │                         │            │ • Return retry_after    │
  │ Window expires:         │            │                         │
  │ • Counter resets        │            │ Window expires:         │
  │                         │            │ • Counter resets        │
  └─────────────────────────┘            └─────────────────────────┘
```

### Encryption

| Aspect | Implementation |
|--------|----------------|
| Algorithm | AES-256-ECB |
| Key length | 32 characters |
| Key storage | totp_config_dg (encrypted DG recommended) |
| Encrypted data | TOTP secrets (Base32) |
| Encoding | Base64 for storage |

---

## High Availability

### HA Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HA Architecture                                      │
└─────────────────────────────────────────────────────────────────────────────┘

            Unit 1 (Active)                      Unit 2 (Standby)
            ───────────────                      ────────────────

        ┌─────────────────────┐              ┌─────────────────────┐
        │ Subtables (memory)  │              │ Subtables (empty)   │
        │ • totp_users        │              │                     │
        │ • totp_ratelimit    │              │                     │
        └─────────────────────┘              └─────────────────────┘
                  │                                    ▲
                  │                                    │
                  ▼                                    │
        ┌─────────────────────┐   Config Sync   ┌─────────────────────┐
        │ Data Groups         │◄───────────────►│ Data Groups         │
        │ • totp_secrets_dg   │                 │ • totp_secrets_dg   │
        │ • totp_config_dg    │                 │ • totp_config_dg    │
        └─────────────────────┘                 └─────────────────────┘
                  │                                    │
                  ▼                                    ▼
        ┌─────────────────────┐              ┌─────────────────────┐
        │ Alert Scripts       │              │ Alert Scripts       │
        │ (manual deploy)     │              │ (manual deploy)     │
        └─────────────────────┘              └─────────────────────┘
```

### Sync Behavior

| Component | Syncs | Notes |
|-----------|-------|-------|
| Data Groups | Yes | Secrets and config synchronized |
| iRules | Yes | Code synchronized |
| Virtual Servers | Yes | Configuration synchronized |
| Access Policies | Yes | APM policies synchronized |
| Subtables | No | Rebuilt via lazy loading |
| Alert Scripts | No | Manual deployment required |
| Rate Limits | No | Reset on failover |

### Failover Behavior

| Event | Impact | Recovery |
|-------|--------|----------|
| Failover | Active sessions lost | Users re-authenticate |
| TMM restart | Subtable cleared | Lazy loading rebuilds |
| Config sync | Data groups updated | Immediate availability |

---

## Design Decisions

### Why Subtables + Data Groups?

| Storage | Purpose | Trade-off |
|---------|---------|-----------|
| Subtables | Fast runtime lookups | Lost on restart |
| Data Groups | Persistence, HA sync | Slower access |
| Combined | Best of both | Complexity |

**Decision:** Use subtables for performance, data groups for persistence, lazy loading to bridge them.

### Why Alert Scripts for Persistence?

| Option | Pros | Cons |
|--------|------|------|
| Direct DG modification | Simple | iRule cannot modify DG |
| External database | Scalable | External dependency |
| Alert scripts | No external deps | Slight delay |

**Decision:** Alert scripts provide persistence without external dependencies while maintaining security (secrets not logged).

### Why Non-Routable Internal API?

| Option | Security | Complexity |
|--------|----------|------------|
| Single VS | Lower | Simple |
| Two VS (external + internal) | Higher | Moderate |
| Separate internal network | Highest | Complex |

**Decision:** Non-routable IP (10.255.255.255) prevents external access to HTTP Auth endpoint while keeping configuration simple.

### Why Lazy Loading?

| Option | Startup Time | Memory Use |
|--------|--------------|------------|
| Load all at startup | Slow (large user base) | Higher |
| Lazy loading | Fast | Efficient |

**Decision:** Lazy loading scales better and provides faster TMM startup.

---

## Technology Stack

### TMOS Components

| Component | Version | Purpose |
|-----------|---------|---------|
| TMOS | 17.1+ | Platform |
| APM | Licensed | Access policies, webtop |
| LTM | Licensed | Virtual servers, iRules |
| Tcl | 8.5 | iRule scripting |

### Standards Compliance

| Standard | Implementation |
|----------|----------------|
| RFC 6238 | TOTP algorithm |
| RFC 4648 | Base32 encoding |
| RFC 4226 | HOTP (base for TOTP) |

### Compatible Authenticator Apps

| App | Platform | Tested |
|-----|----------|--------|
| Google Authenticator | iOS, Android | Yes |
| Microsoft Authenticator | iOS, Android | Yes |
| Authy | iOS, Android, Desktop | Yes |
| 1Password | iOS, Android, Desktop | Yes |
| Bitwarden | iOS, Android, Desktop | Yes |
| FreeOTP | iOS, Android | Yes |

---

## Limitations

### Technical Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| TMOS Tcl 8.5 | No binary literals, limited format | Custom procedures |
| No cross-iRule static:: | Config in data group | Load from DG |
| No exec in iRules | Cannot call external commands | Alert scripts |
| No DG modification in iRules | Cannot persist directly | Alert scripts |

### Operational Limitations

| Limitation | Impact | Consideration |
|------------|--------|---------------|
| Session not mirrored by default | Re-auth after failover | Enable mirroring if needed |
| Rate limits not synced | Reset on failover | Acceptable for most cases |
| Alert script delay | ~2-5 second persistence | Acceptable latency |

### Scale Limitations

| Metric | Recommended Max | Notes |
|--------|-----------------|-------|
| Enrolled users | 100,000 | Data group size |
| Concurrent sessions | Per APM license | License dependent |
| Verifications/second | ~1000 | Platform dependent |

---

## Documentation Map

| Section | Content |
|---------|---------|
| [00 - Quick Start](00-quick-start.md) | Rapid deployment checklist |
| [01 - Overview](01-overview.md) | This document |
| [02 - Prerequisites](01-prerequisites.md) | Platform requirements |
| [03 - Network Configuration](02-network-configuration.md) | VLANs, self-IPs, routing |
| [04 - SSL Certificates](03-ssl-certificates.md) | Certificates and profiles |
| [05 - User Database](04-user-database.md) | LocalDB and AD |
| [06 - TOTP Enrollment](05-totp-enrollment.md) | Enrollment infrastructure |
| [07 - TOTP Verification API](06-totp-verification-api.md) | API configuration |
| [08 - Persistence and HA](07-persistence-and-ha.md) | Storage and sync |
| [09 - MFA Portal](08-mfa-portal.md) | Portal configuration |
| [10 - HA Configuration](09-ha-configuration.md) | High availability |
| [11 - Administration](10-administration.md) | Admin procedures |
| [12 - Testing](11-testing.md) | Test procedures |

---

## Next Steps

Proceed to [01 - Prerequisites](01-prerequisites.md) to verify platform requirements before beginning deployment.