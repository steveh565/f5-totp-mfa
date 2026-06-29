# Configuration Values Reference

This document lists all configuration values that you need to customize for your environment before deploying the solution. Default example values use the `mfa-demo.local` domain — replace these with values appropriate for your deployment.

> **Note:** Values marked with *(auto-generated)* are created during the setup process using `openssl rand` commands. Values marked with *(your environment)* must be provided based on your specific infrastructure.

## Network Configuration

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| External VLAN interface | `1.1` | Physical interface for external VLAN | Network Config |
| Internal VLAN interface | `1.2` | Physical interface for internal VLAN | Network Config |
| HA VLAN interface | `1.3` | Physical interface for HA VLAN | Network Config |
| External self-IP | `10.1.1.1/24` | BIG-IP external interface address | Network Config |
| Internal self-IP | `10.1.2.1/24` | BIG-IP internal interface address | Network Config |
| HA self-IP | `10.1.3.1/24` | BIG-IP HA interface address | Network Config |
| External floating IP | `10.1.1.2/24` | Shared HA external address | Network Config |
| Internal floating IP | `10.1.2.2/24` | Shared HA internal address | Network Config |
| Default gateway | `10.1.1.254` | Network default route | Network Config |
| NTP servers | `0.pool.ntp.org`, `1.pool.ntp.org` | Time synchronization servers | Prerequisites |
| DNS servers | `8.8.8.8`, `8.8.4.4` | Name resolution servers | Prerequisites |

## SSL Certificates

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| Key/cert name (ECC) | `mfa-ecc` | ECC private key and certificate name | SSL Certificates |
| Key/cert name (RSA) | `mfa-rsa` | RSA private key and certificate name | SSL Certificates |
| Common name | `*.mfa-demo.local` | Certificate wildcard CN | SSL Certificates |
| Organization | `MFA Demo` | Certificate organization field | SSL Certificates |
| Country | `CA` | Certificate country code | SSL Certificates |
| SAN entries | `DNS:totp-enroll.mfa-demo.local,...` | Subject Alternative Names | SSL Certificates |
| Client SSL profile | `mfa-clientssl` | Front-end SSL profile name | SSL Certificates |
| Server SSL profile | `mfa-serverssl` | Back-end SSL profile name | SSL Certificates |

## Virtual Server Addresses

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| Enrollment VS | `10.1.1.100:443` | TOTP enrollment virtual server | TOTP Enrollment |
| Verify API VS (external) | `10.1.1.101:443` | External TOTP verification API | Verify API |
| Verify API VS (internal) | `10.255.255.255:80` | Internal API for HTTP Auth agent | Verify API |
| MFA Portal VS | `10.1.1.102:443` | MFA portal with webtop | MFA Portal |
| Admin UI VS | `10.1.1.104:443` | Administration web UI | Administration |

## DNS Hostnames

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| Enrollment hostname | `totp-enroll.mfa-demo.local` | Enrollment VS DNS name | TOTP Enrollment |
| API hostname | `totp-api.mfa-demo.local` | Verification API DNS name | Verify API |
| Portal hostname | `portal.mfa-demo.local` | MFA portal DNS name | MFA Portal |
| Domain suffix | `mfa-demo.local` | Base domain for all services | All sections |

## Authentication Backend

### Option A — Local User Database

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| Local DB instance name | `mfa_users_db` | APM local user database name | User Database |
| Lockout threshold | `5` | Failed attempts before lockout | User Database |
| Auto-unlock interval | `300` | Seconds until auto-unlock | User Database |
| User group name | `mfaUsers` | Default user group | User Database |
| Admin group name | `mfaAdmins` | Admin user group | User Database |

### Option B — Active Directory

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| AAA server name | `mfa_ad_aaa` | AD AAA server object name | User Database |
| AD domain name | *(your environment)* | Active Directory domain | User Database |
| AD server IP | *(your environment)* | Domain controller address | User Database |
| AD admin credentials | *(your environment)* | Service account for AD queries | User Database |
| Group cache | `30` | Group cache timeout (seconds) | User Database |
| Password cache | `30` | Password cache timeout (seconds) | User Database |

## TOTP Configuration (totp_config_dg)

| Parameter | Example Value | Description | Guide Section |
|---|---|---|---|
| `encryption_key` | *(auto-generated)* | AES-256 key for secret encryption — **must generate** | TOTP Enrollment |
| `api_key` | *(auto-generated)* | Shared API authentication key — **must generate** | TOTP Enrollment |
| `issuer` | `mfa-demo` | TOTP issuer label in authenticator apps | TOTP Enrollment |
| `rate_max_attempts` | `5` | Verification: max failed attempts before lockout | TOTP Enrollment |
| `rate_window_seconds` | `300` | Verification: lockout window (seconds) | TOTP Enrollment |
| `enroll_rate_max_attempts` | `3` | Enrollment: max failed confirmations before lockout | TOTP Enrollment |
| `enroll_rate_window_seconds` | `600` | Enrollment: lockout window (seconds) | TOTP Enrollment |

### Generating Keys

```bash
# Generate the encryption key (AES-256, Base64 encoded)
TOTP_ENC_KEY=$(openssl rand -base64 32)
echo "Encryption Key: $TOTP_ENC_KEY"

# Generate the API key (hex encoded)
TOTP_API_KEY=$(openssl rand -hex 32)
echo "API Key: $TOTP_API_KEY"