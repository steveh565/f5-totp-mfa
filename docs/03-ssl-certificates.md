# 03 - SSL Certificates

This section covers SSL certificate generation, certificate management, and SSL profile configuration for the TOTP MFA solution.

---

## Certificate Overview

All user-facing virtual servers require SSL/TLS encryption. This solution uses a wildcard or SAN certificate to secure multiple services:

| Virtual Server | FQDN | Certificate Required |
|----------------|------|----------------------|
| vs_totp_enroll | totp-enroll.mfa-demo.local | Yes |
| vs_totp_api | totp-api.mfa-demo.local | Yes |
| vs_mfa_portal | portal.mfa-demo.local | Yes |
| vs_totp_admin | totp-admin.mfa-demo.local | Yes |
| vs_totp_api_internal | (non-routable) | No (HTTP only) |

### Certificate Options

| Option | Use Case | Pros | Cons |
|--------|----------|------|------|
| Self-signed (ECC) | Lab, development, PoC | Fast, modern crypto, smaller keys | Browser warnings |
| Self-signed (RSA) | Legacy compatibility | Wide compatibility | Larger keys, browser warnings |
| CA-signed | Production | Trusted by browsers | Requires CA infrastructure |
| Wildcard | Multiple subdomains | Single cert for all services | Broader exposure if compromised |
| SAN | Specific hosts | Precise scope | Must list all hosts |

---

## Option A — Self-Signed ECC Certificate (Recommended)

ECC (Elliptic Curve Cryptography) provides equivalent security with smaller key sizes and faster performance.

### Generate ECC Key and Certificate

```bash
tmsh create sys crypto key mfa-ecc {
    key-type ec-private
    curve-name secp384r1
    gen-certificate {
        common-name "*.mfa-demo.local"
        country "CA"
        state "Ontario"
        city "Toronto"
        organization "MFA Demo"
        ou "IT Security"
        lifetime 3650
        subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
    }
}
```

**Single-line version:**

```bash
tmsh create sys crypto key mfa-ecc key-type ec-private curve-name secp384r1 gen-certificate common-name "*.mfa-demo.local" country "CA" state "Ontario" city "Toronto" organization "MFA Demo" ou "IT Security" lifetime 3650 subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

### Verify ECC Certificate

```bash
# List the key
tmsh list sys crypto key mfa-ecc

# List the certificate
tmsh list sys crypto cert mfa-ecc
```

Expected key output:

```
sys crypto key mfa-ecc {
    curve-name secp384r1
    key-size 384
    key-type ec-private
    security-type normal
}
```

### View Certificate Details

```bash
openssl x509 -in /config/filestore/files_d/Common_d/certificate_d/:Common:mfa-ecc.crt_* -text -noout
```

---

## Option B — Self-Signed RSA Certificate

RSA certificates provide broader compatibility with legacy systems and older clients.

### Generate RSA Key and Certificate

```bash
tmsh create sys crypto key mfa-rsa {
    key-size 2048
    gen-certificate {
        common-name "*.mfa-demo.local"
        country "CA"
        state "Ontario"
        city "Toronto"
        organization "MFA Demo"
        ou "IT Security"
        lifetime 3650
        subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
    }
}
```

**Single-line version:**

```bash
tmsh create sys crypto key mfa-rsa key-size 2048 gen-certificate common-name "*.mfa-demo.local" country "CA" state "Ontario" city "Toronto" organization "MFA Demo" ou "IT Security" lifetime 3650 subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

### RSA Key Size Recommendations

| Key Size | Security Level | Use Case |
|----------|----------------|----------|
| 2048 | Minimum acceptable | Legacy compatibility |
| 3072 | Good | Balanced security/performance |
| 4096 | High | Maximum security |

For 4096-bit RSA:

```bash
tmsh create sys crypto key mfa-rsa key-size 4096 gen-certificate common-name "*.mfa-demo.local" country "CA" lifetime 3650 subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

### Verify RSA Certificate

```bash
tmsh list sys crypto key mfa-rsa
tmsh list sys crypto cert mfa-rsa
```

---

## Option C — CA-Signed Certificate

For production environments, use certificates signed by your organization's Certificate Authority or a public CA.

### Generate Certificate Signing Request (CSR)

**ECC CSR:**

```bash
tmsh create sys crypto key mfa-ecc key-type ec-private curve-name secp384r1 gen-csr common-name "*.mfa-demo.local" country "CA" state "Ontario" city "Toronto" organization "MFA Demo" ou "IT Security" subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

**RSA CSR:**

```bash
tmsh create sys crypto key mfa-rsa key-size 2048 gen-csr common-name "*.mfa-demo.local" country "CA" state "Ontario" city "Toronto" organization "MFA Demo" ou "IT Security" subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

### Export CSR

```bash
# Find the CSR file
ls -la /config/filestore/files_d/Common_d/certificate_request_d/

# View CSR content
cat /config/filestore/files_d/Common_d/certificate_request_d/:Common:mfa-ecc.csr_*
```

Submit the CSR to your Certificate Authority.

### Import Signed Certificate

After receiving the signed certificate from your CA:

**Via GUI (recommended):**

1. Navigate to System → Certificate Management → Traffic Certificate Management → SSL Certificate List
2. Click Import
3. Import Type: Certificate
4. Certificate Name: `mfa-ecc` (must match key name)
5. Certificate Source: Upload File or Paste Text
6. Upload the signed certificate

**Via tmsh:**

```bash
# Copy certificate to BIG-IP
scp signed-cert.crt admin@bigip.mfa-demo.local:/var/tmp/

# Install certificate
tmsh install sys crypto cert mfa-ecc from-local-file /var/tmp/signed-cert.crt
```

### Import CA Chain (If Required)

If your CA provides intermediate certificates:

```bash
# Import intermediate CA
tmsh install sys crypto cert intermediate-ca from-local-file /var/tmp/intermediate.crt

# Import root CA (if not already trusted)
tmsh install sys crypto cert root-ca from-local-file /var/tmp/root-ca.crt
```

---

## SSL Profile Configuration

SSL profiles define the SSL/TLS settings applied to virtual servers.

### Client SSL Profile — ECC Certificate

```bash
tmsh create ltm profile client-ssl mfa-clientssl {
    defaults-from clientssl
    cert-key-chain add {
        mfa-ecc {
            cert mfa-ecc
            key mfa-ecc
        }
    }
}
```

### Client SSL Profile — RSA Certificate

```bash
tmsh create ltm profile client-ssl mfa-clientssl {
    defaults-from clientssl
    cert mfa-rsa
    key mfa-rsa
}
```

> **Note:** ECC certificates use the `cert-key-chain add { }` syntax. RSA certificates use the flat `cert` and `key` syntax. Both require `defaults-from clientssl`.

### Client SSL Profile — CA-Signed with Chain

For CA-signed certificates with intermediate CAs:

```bash
tmsh create ltm profile client-ssl mfa-clientssl {
    defaults-from clientssl
    cert-key-chain add {
        mfa-ecc {
            cert mfa-ecc
            key mfa-ecc
            chain intermediate-ca
        }
    }
}
```

### Verify Client SSL Profile

```bash
tmsh list ltm profile client-ssl mfa-clientssl
```

Expected output (ECC):

```
ltm profile client-ssl mfa-clientssl {
    app-service none
    cert-key-chain {
        mfa-ecc {
            cert mfa-ecc
            key mfa-ecc
        }
    }
    defaults-from clientssl
    inherit-ca-certkeychain true
    inherit-certkeychain false
}
```

---

## Server SSL Profile

A server SSL profile is required for the alert scripts to communicate with the external API virtual server via HTTPS.

### Server SSL Profile — Insecure (Lab/Self-Signed)

For lab environments with self-signed certificates:

```bash
tmsh create ltm profile server-ssl mfa-serverssl {
    defaults-from serverssl-insecure-compatible
}
```

This profile disables certificate verification, suitable only for lab/development environments.

### Server SSL Profile — Secure (Production)

For production with proper certificate validation:

```bash
tmsh create ltm profile server-ssl mfa-serverssl {
    defaults-from serverssl
    ca-file ca-bundle.crt
    server-name totp-api.mfa-demo.local
}
```

### Verify Server SSL Profile

```bash
tmsh list ltm profile server-ssl mfa-serverssl
```

---

## SSL/TLS Security Settings

### Recommended Cipher Suites

For modern security, restrict cipher suites to strong algorithms:

```bash
tmsh modify ltm profile client-ssl mfa-clientssl {
    ciphers "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS"
}
```

### TLS Version Settings

Disable older TLS versions:

```bash
tmsh modify ltm profile client-ssl mfa-clientssl {
    options { dont-insert-empty-fragments no-tlsv1 no-tlsv1.1 }
}
```

This allows only TLS 1.2 and TLS 1.3.

### Complete Hardened Profile

```bash
tmsh create ltm profile client-ssl mfa-clientssl-hardened {
    defaults-from clientssl
    cert-key-chain add {
        mfa-ecc {
            cert mfa-ecc
            key mfa-ecc
        }
    }
    ciphers "ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:!aNULL:!MD5:!DSS:!3DES:!RC4"
    options { dont-insert-empty-fragments no-tlsv1 no-tlsv1.1 }
}
```

---

## Certificate Management

### View Certificate Expiration

```bash
# List all certificates with expiration
tmsh show sys crypto cert | grep -A2 "Expiration"

# Check specific certificate
openssl x509 -in /config/filestore/files_d/Common_d/certificate_d/:Common:mfa-ecc.crt_* -enddate -noout
```

### Certificate Renewal — Self-Signed

For self-signed certificates, generate a new certificate with the same key name:

```bash
# Delete existing certificate (keeps key)
tmsh delete sys crypto cert mfa-ecc

# Generate new certificate
tmsh create sys crypto cert mfa-ecc {
    key mfa-ecc
    common-name "*.mfa-demo.local"
    lifetime 3650
    subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
}
```

### Certificate Renewal — CA-Signed

1. Generate new CSR (reuse existing key):

```bash
tmsh create sys crypto csr mfa-ecc-renewal key mfa-ecc common-name "*.mfa-demo.local" subject-alternative-name "DNS:totp-enroll.mfa-demo.local,DNS:totp-api.mfa-demo.local,DNS:portal.mfa-demo.local,DNS:totp-admin.mfa-demo.local"
```

2. Submit CSR to CA
3. Import new certificate (overwrites existing)

### Export Certificate and Key

For backup or migration:

```bash
# Export certificate
tmsh show sys crypto cert mfa-ecc | grep -A100 "BEGIN CERTIFICATE"

# Export key (requires admin access)
tmsh show sys crypto key mfa-ecc | grep -A100 "BEGIN"
```

> **Warning:** Protect exported private keys. Never transmit unencrypted over insecure channels.

---

## Troubleshooting

### Certificate Not Appearing in Profile List

```bash
# Verify certificate exists
tmsh list sys crypto cert

# Verify key exists
tmsh list sys crypto key

# Certificate and key names must match for pairing
```

### SSL Handshake Failures

```bash
# Test SSL connection
openssl s_client -connect totp-enroll.mfa-demo.local:443 -servername totp-enroll.mfa-demo.local

# Check virtual server SSL profile
tmsh list ltm virtual vs_totp_enroll profiles
```

### Certificate Chain Issues

```bash
# Verify certificate chain
openssl s_client -connect totp-enroll.mfa-demo.local:443 -showcerts

# Check for chain gaps in output
```

### Browser Certificate Warnings

For self-signed certificates, browsers will display warnings. Options:

1. **Accept the warning** — Click "Advanced" and proceed (lab/testing)
2. **Import CA certificate** — Add self-signed cert to browser/OS trust store
3. **Use CA-signed certificate** — Production recommendation

**Export certificate for client import:**

```bash
openssl x509 -in /config/filestore/files_d/Common_d/certificate_d/:Common:mfa-ecc.crt_* -outform PEM -out mfa-demo-ca.crt
```

---

## Configuration Summary

After completing this section, you should have:

| Component | ECC | RSA |
|-----------|-----|-----|
| Private Key | mfa-ecc (secp384r1) | mfa-rsa (2048/4096-bit) |
| Certificate | mfa-ecc | mfa-rsa |
| Client SSL Profile | mfa-clientssl | mfa-clientssl |
| Server SSL Profile | mfa-serverssl | mfa-serverssl |

### Quick Reference — Profile Syntax

| Certificate Type | Client SSL Profile Syntax |
|------------------|---------------------------|
| ECC | `cert-key-chain add { name { cert X key Y } }` |
| RSA | `cert X key Y` (flat syntax) |
| With Chain | `cert-key-chain add { name { cert X key Y chain Z } }` |

---

## Save Configuration

```bash
tmsh save sys config
```

---

## Next Steps

Proceed to [04 - User Database](04-user-database.md) to configure the authentication backend (Local DB or Active Directory).