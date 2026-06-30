# 01 - Prerequisites

This section covers the platform requirements, licensing, and foundational services that must be in place before deploying the TOTP MFA solution.

---

## Platform Requirements

### BIG-IP Version

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| TMOS Version | 17.1.0 | 17.5.1.5 |
| Architecture | Virtual or Hardware | Any supported platform |

> **Note:** This solution was developed and tested on TMOS 17.5.1.5. Earlier versions may work but have not been validated. The iRule code is compatible with TMOS Tcl 8.5 limitations.

### Module Provisioning

Both APM and LTM must be provisioned at `nominal` level:

```bash
# Verify current provisioning
tmsh show sys provision | grep -E "ltm|apm"
```

Expected output:
```
ltm         nominal
apm         nominal
```

If not provisioned, enable modules:

```bash
# Provision LTM and APM (requires reboot)
tmsh modify sys provision ltm level nominal
tmsh modify sys provision apm level nominal
tmsh save sys config
reboot
```

> **Warning:** Changing provisioning levels requires a system reboot and may take several minutes.

---

## Licensing Requirements

### APM License

The Access Policy Manager license must include:

| Feature | Requirement |
|---------|-------------|
| Access Sessions | Sufficient for concurrent users |
| Connectivity Profile | Required for portal VS |
| Webtop | Required for user self-service |

Verify APM license:

```bash
tmsh show sys license | grep -i "access"
```

Look for entries indicating APM access sessions (e.g., `APM, Max Access Sessions`).

### LTM License

Standard LTM licensing is sufficient. No specific add-ons required.

---

## Time Synchronization (NTP)

TOTP authentication is time-sensitive. The BIG-IP system clock **must** be synchronized with accurate time sources. A time drift of more than 30 seconds will cause TOTP code validation failures.

### Configure NTP Servers

```bash
# Configure NTP servers
tmsh modify sys ntp servers replace-all-with { 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org }

# Set timezone (adjust for your location)
tmsh modify sys ntp timezone America/Toronto

tmsh save sys config
```

### Verify NTP Synchronization

```bash
ntpq -p
```

Expected output shows `*` next to the active server:

```
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*0.pool.ntp.org  .GPS.            1 u   42   64  377   12.345   -0.123   1.234
+1.pool.ntp.org  .GPS.            1 u   38   64  377   15.678    0.456   2.345
+2.pool.ntp.org  .PPS.            1 u   51   64  377   18.901   -0.789   1.567
```

| Symbol | Meaning |
|--------|---------|
| `*` | Current sync source |
| `+` | Candidate for sync |
| `-` | Excluded from selection |
| (blank) | Rejected or unreachable |

### Troubleshooting NTP

If no server shows `*` after several minutes:

```bash
# Check NTP daemon status
bigstart status ntpd

# Restart NTP daemon
bigstart restart ntpd

# Force immediate sync (use sparingly)
ntpdate -u 0.pool.ntp.org
```

> **Important:** The `time_skew` parameter in `totp_config_dg` allows a tolerance window (default: 1 interval = ±30 seconds). This accommodates minor drift but does not replace proper NTP configuration.

---

## DNS Configuration

### BIG-IP DNS Resolution

The BIG-IP must be able to resolve hostnames for:

- NTP servers (if using FQDNs)
- Active Directory domain controllers (if using AD authentication)
- External services (if applicable)

Configure DNS servers:

```bash
tmsh modify sys dns name-servers add { 10.1.1.10 10.1.1.11 }
tmsh modify sys dns search add { mfa-demo.local corp.example.com }
tmsh save sys config
```

Verify DNS resolution:

```bash
nslookup 0.pool.ntp.org
dig mfa-demo.local
```

### Client DNS Resolution

To resolve hostnames on the BIG-IP itself, you must use TMSH to modify the hosts file (do not edit it directly):

```bash
tmsh modify sys global-settings hostname bigip1.mfa-demo.local

tmsh modify /sys hosts {
    records add {
        totp-enroll.mfa-demo.local { aliases none address 10.1.1.100 }
        totp-api.mfa-demo.local { aliases none address 10.1.1.101 }
        portal.mfa-demo.local { aliases none address 10.1.1.102 }
        admin.mfa-demo.local { aliases none address 10.1.1.104 }
    }
}

tmsh save sys config
```

Clients accessing the MFA solution must be able to resolve the service FQDNs:

| FQDN | IP Address | Service |
|------|------------|---------|
| portal.mfa-demo.local | 10.1.1.102 | MFA Portal |
| totp-enroll.mfa-demo.local | 10.1.1.100 | TOTP Enrollment |
| totp-api.mfa-demo.local | 10.1.1.101 | TOTP API (External) |
| totp-admin.mfa-demo.local | 10.1.1.104 | Admin UI |

**Option A — DNS Server (Production):**

Add A records to your DNS server for each FQDN.

**Option B.1 — Hosts File (Lab/Testing):**

```bash
# On client workstations
cat >> /etc/hosts << 'EOF'
10.1.1.100  totp-enroll.mfa-demo.local
10.1.1.101  totp-api.mfa-demo.local
10.1.1.102  portal.mfa-demo.local
10.1.1.104  totp-admin.mfa-demo.local
EOF
```

Windows clients: Edit `C:\Windows\System32\drivers\etc\hosts`

---

## Administrative Access

### SSH Access

SSH access to the BIG-IP is required for:

- Deploying alert scripts to `/config/totp/`
- Configuring `/config/user_alert.conf`
- Uploading iFile content
- Troubleshooting and log review

Verify SSH access:

```bash
ssh admin@bigip.mfa-demo.local
```

### GUI Access

The BIG-IP Configuration Utility (GUI) is required for:

- Creating HTTP AAA objects (Custom Post type is GUI-only)
- Building Access Policies in the Visual Policy Editor (VPE)
- Creating webtop resources and links

Access via: `https://bigip.mfa-demo.local/tmui`

### TMSH Access

Most configuration can be performed via `tmsh` commands. This guide provides `tmsh` commands wherever possible for:

- Repeatability and scripting
- Documentation and version control
- Disaster recovery procedures

---

## Network Prerequisites

### IP Address Allocation

Reserve the following IP addresses before deployment:

| Purpose | Example IP | Notes |
|---------|------------|-------|
| BIG-IP Management | 192.168.1.100 | Out-of-band management |
| External Self-IP | 10.1.1.1 | External VLAN interface |
| Internal Self-IP | 10.1.2.1 | Internal VLAN interface |
| TOTP Enrollment VS | 10.1.1.100 | User-facing |
| TOTP API VS (External) | 10.1.1.101 | External API access |
| MFA Portal VS | 10.1.1.102 | User-facing |
| Admin UI VS | 10.1.1.104 | Administrative access |
| TOTP API VS (Internal) | 10.255.255.255 | Non-routable, HTTP Auth |

> **Note:** The internal API VS (10.255.255.255) uses a non-routable address intentionally. It is only accessed by the APM HTTP Auth agent from the BIG-IP itself.

### Firewall Requirements

If firewalls exist between clients and the BIG-IP:

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Users | 10.1.1.100 | 443 | TCP | TOTP Enrollment |
| Users | 10.1.1.102 | 443 | TCP | MFA Portal |
| Admins | 10.1.1.104 | 443 | TCP | Admin UI |
| External Apps | 10.1.1.101 | 443 | TCP | TOTP API (if needed) |

---

## Software and Tools

### Authenticator Apps

Users will need a TOTP-compatible authenticator app on their mobile device:

| App | Platform | Notes |
|-----|----------|-------|
| Google Authenticator | iOS, Android | Most common |
| Microsoft Authenticator | iOS, Android | Enterprise-friendly |
| Authy | iOS, Android, Desktop | Multi-device sync |
| 1Password | iOS, Android, Desktop | Password manager integration |
| Bitwarden | iOS, Android, Desktop | Open source option |

Any RFC 6238-compliant TOTP app will work with this solution.

### Administrator Tools

For deployment and testing:

| Tool | Purpose |
|------|---------|
| SSH client | BIG-IP command line access |
| SCP/SFTP client | File transfer to BIG-IP |
| Web browser | GUI access, testing |
| curl | API testing |
| Text editor | iRule editing |

---

## Pre-Deployment Checklist

Before proceeding to network configuration, verify:

- [ ] BIG-IP TMOS 17.1+ installed
- [ ] LTM provisioned at nominal level
- [ ] APM provisioned at nominal level
- [ ] APM license includes sufficient access sessions
- [ ] NTP configured and synchronized (verify with `ntpq -p`)
- [ ] DNS servers configured on BIG-IP
- [ ] SSH access to BIG-IP confirmed
- [ ] GUI access to BIG-IP confirmed
- [ ] IP addresses allocated for all virtual servers
- [ ] DNS records created (or hosts file entries for lab)
- [ ] Firewall rules in place (if applicable)

---

## Next Steps

Once all prerequisites are met, proceed to [02 - Network Configuration](02-network-configuration.md) to configure VLANs, self-IPs, and routing.