# TOTP MFA Solution

TOTP-based Multi-Factor Authentication for F5 BIG-IP APM + LTM

## Overview

This repository provides a complete MFA solution for F5 BIG-IP
TMOS 17.5.1.5 with no external dependencies, suitable for use with Google Authenticator or Microsoft Authenticator.

## Features

- TOTP enrollment with QR code self-service
- Self-service re-enrollment
- Rate limiting on API and enrollment
- Web-based administration UI
- HA support with automatic persistence
- Active Directory and Local DB authentication support

## Architecture

```mermaid
flowchart TB
    subgraph Client
        Browser[Web Browser]
    end

    subgraph BIG-IP["BIG-IP TMOS 17.5.1.5"]
        subgraph Portal["MFA Portal (10.1.1.102:443)"]
            VS_MFA[vs_mfa_portal]
            AP_MFA[ap_mfa_portal]
            IRULE_TOTP_MFA[irule_idp_mfa]
        end

        subgraph Enrollment["TOTP Enrollment (10.1.1.100:443)"]
            VS_ENROLL[vs_totp_enroll]
            AP_ENROLL[ap_totp_enroll]
            IRULE_TOTP_ENROLL[irule_totp_enroll]
        end

        subgraph API["TOTP API"]
            VS_API_EXT["vs_totp_api (10.1.1.101:443)"]
            VS_API_INT["vs_totp_api_internal (10.255.255.255:80)"]
            IRULE_TOTP_API[irule_totp_api]
        end

        subgraph Admin["Admin UI (10.1.1.104:443)"]
            VS_ADMIN[vs_totp_admin]
            IRULE_TOTP_ADMIN[irule_totp_admin_ui]
        end

        subgraph Shared["Shared Components"]
            IRULE_TOTP_SHARED[irule_totp_shared]
            TABLE_USERS[(totp_users subtable)]
            DG_SECRETS[(totp_secrets_dg)]
            DG_CONFIG[(totp_config_dg)]
            IFILE[qrcode_js iFile]
        end

        subgraph Auth["Authentication Backend"]
            LOCAL_DB[Local User DB]
            AD[Active Directory]
        end

        subgraph Alerts["Alert Infrastructure"]
            ALERT_CONF["/config/user_alert.conf"]
            ENROLL_SH[totp_enroll.sh]
            UNENROLL_SH[totp_unenroll.sh]
        end
    end

    subgraph HA["HA Peer"]
        PEER[BIG-IP Standby]
    end

    Browser -->|HTTPS| VS_MFA
    VS_MFA --> AP_MFA
    AP_MFA -->|Option A| LOCAL_DB
    AP_MFA -->|Option B| AD
    AP_MFA -->|Enrollment Check| IRULE_TOTP_MFA
    IRULE_TOTP_MFA --> IRULE_TOTP_SHARED
    AP_MFA -->|TOTP Verify| VS_API_INT
    AP_MFA -->|Not Enrolled| VS_ENROLL

    VS_MFA -->|Webtop Link| VS_ENROLL
    VS_MFA -->|Webtop Link| VS_ADMIN

    VS_ENROLL --> IRULE_TOTP_ENROLL
    IRULE_TOTP_ENROLL --> IRULE_TOTP_SHARED
    IRULE_TOTP_ENROLL -->|QR Code| IFILE

    VS_API_INT --> IRULE_TOTP_API
    VS_API_EXT --> IRULE_TOTP_API
    IRULE_TOTP_API --> IRULE_TOTP_SHARED

    IRULE_TOTP_SHARED -->|Read/Write| TABLE_USERS
    IRULE_TOTP_SHARED -->|Read| DG_CONFIG
    IRULE_TOTP_SHARED -->|Read| DG_SECRETS
    IRULE_TOTP_SHARED -->|RULE_INIT| DG_SECRETS

    TABLE_USERS -->|log alert| ALERT_CONF
    ALERT_CONF -->|Enroll| ENROLL_SH
    ALERT_CONF -->|Unenroll| UNENROLL_SH
    ENROLL_SH -->|API call| VS_API_INT
    ENROLL_SH -->|tmsh modify| DG_SECRETS
    UNENROLL_SH -->|tmsh modify| DG_SECRETS

    DG_SECRETS -->|configsync| PEER
    DG_CONFIG -->|configsync| PEER
```

## Components

| Component | Description |
|---|---|
| [irule_totp_shared](irules/irule_totp_shared.tcl) | Shared TOTP procs |
| [irule_totp_enroll](irules/irule_totp_enroll.tcl) | Enrollment flow |
| [irule_totp_api](irules/irule_totp_api.tcl) | API flow |
| [irule_totp_admin_ui](irules/irule_totp_admin_ai.tcl) | Admin UI flow |
| [irule_idp_mfa](irules/irule_idp_mfa.tcl) | APM MFA flow |
| [totp_enroll.sh](scripts/totp_enroll.sh) | User Enrollment automation script |
| [totp_unenroll.sh](scripts/totp_unenroll.sh) | User Unenrollment automation script |
| [user_alert.conf](config/user_alert.conf) | Custom Alert definitions to trigger enroll/unenroll automation |
| [qrcode.js](ifiles/qrcode.js) | QR Code JavaScript |

## Requirements

- BIG-IP TMOS 17.5.1.5
- APM + LTM provisioned

## License

[Apache 2.0]