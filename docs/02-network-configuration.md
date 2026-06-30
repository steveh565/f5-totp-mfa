# 02 - Network Configuration

This section covers VLAN creation, self-IP assignment, and routing configuration for the TOTP MFA solution.

---

## Network Architecture Overview

The solution uses a minimum of two network segments:

| Segment | Purpose | Example Subnet |
|---------|---------|----------------|
| External | User-facing services (portal, enrollment, admin) | 10.1.1.0/24 |
| Internal | Non-routable API endpoint for HTTP Auth agent | 10.255.255.0/24 |

For HA deployments, add:

| Segment | Purpose | Example Subnet |
|---------|---------|----------------|
| HA | Device-to-device synchronization | 10.1.3.0/24 |

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Clients                                   │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      │ HTTPS (443)
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     External VLAN (10.1.1.0/24)                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │ Enrollment   │ │ API          │ │ MFA Portal   │ │ Admin UI    │ │
│  │ 10.1.1.100   │ │ 10.1.1.101   │ │ 10.1.1.102   │ │ 10.1.1.104  │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └─────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ BIG-IP Internal
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Internal VLAN (10.255.255.0/24)                  │
│                    ┌────────────────────────────┐                   │
│                    │ API Internal (HTTP Auth)   │                   │
│                    │ 10.255.255.255:80          │                   │
│                    └────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

> **Note:** The internal API virtual server (10.255.255.255) is intentionally non-routable. It handles HTTP Auth agent requests originating from APM on the BIG-IP itself.

---

## VLAN Configuration

### External VLAN

The external VLAN carries all user-facing traffic:

```bash
tmsh create net vlan external {
    interfaces add { 1.1 { untagged } }
    mtu 1500
}
```

**With VLAN tagging (trunk port):**

```bash
tmsh create net vlan external {
    interfaces add { 1.1 { tagged } }
    tag 100
    mtu 1500
}
```

### Internal VLAN

The internal VLAN hosts the non-routable API endpoint:

```bash
tmsh create net vlan internal {
    interfaces add { 1.2 { untagged } }
    mtu 1500
}
```

**With VLAN tagging:**

```bash
tmsh create net vlan internal {
    interfaces add { 1.2 { tagged } }
    tag 200
    mtu 1500
}
```

### HA VLAN (Optional — HA Deployments Only)

For high availability configurations:

```bash
tmsh create net vlan ha {
    interfaces add { 1.3 { untagged } }
    mtu 1500
}
```

### Verify VLANs

```bash
tmsh list net vlan
```

Expected output:

```
net vlan external {
    interfaces {
        1.1 { }
    }
    mtu 1500
    tag 4094
}
net vlan internal {
    interfaces {
        1.2 { }
    }
    mtu 1500
    tag 4093
}
```

---

## Self-IP Configuration

### External Self-IP

```bash
tmsh create net self external-self {
    address 10.1.1.1/24
    vlan external
    allow-service default
}
```

### Internal Self-IP

```bash
tmsh create net self internal-self {
    address 10.255.255.254/24
    vlan internal
    allow-service default
}
```

### HA Self-IP (Optional — HA Deployments Only)

```bash
tmsh create net self ha-self {
    address 10.1.3.1/24
    vlan ha
    allow-service default
}
```

### Floating Self-IPs (HA Deployments Only)

Floating IPs are shared between HA peers and move with the active unit:

```bash
# External floating IP
tmsh create net self external-floating {
    address 10.1.1.2/24
    vlan external
    traffic-group traffic-group-1
    allow-service default
}

# Internal floating IP (if needed)
tmsh create net self internal-floating {
    address 10.255.255.253/24
    vlan internal
    traffic-group traffic-group-1
    allow-service default
}
```

### Verify Self-IPs

```bash
tmsh list net self
```

Expected output:

```
net self external-self {
    address 10.1.1.1/24
    allow-service {
        default
    }
    traffic-group traffic-group-local-only
    vlan external
}
net self internal-self {
    address 10.255.255.254/24
    allow-service {
        default
    }
    traffic-group traffic-group-local-only
    vlan internal
}
```

---

## Routing Configuration

### Default Route

Configure the default gateway for outbound traffic:

```bash
tmsh create net route default-route {
    gw 10.1.1.254
    network default
}
```

### Verify Routes

```bash
tmsh list net route
```

Expected output:

```
net route default-route {
    gw 10.1.1.254
    network default
}
```

### Additional Routes (If Required)

If your environment requires specific routes to reach backend services:

```bash
# Route to AD domain controllers
tmsh create net route ad-servers {
    gw 10.1.1.254
    network 10.10.0.0/16
}

# Route to management network
tmsh create net route mgmt-network {
    gw 10.1.1.254
    network 192.168.0.0/24
}
```

---

## Port Lockdown Settings

The `allow-service` setting on self-IPs controls which services are accessible on that IP. Options include:

| Setting | Services Allowed |
|---------|------------------|
| `all` | All services |
| `default` | Common services (SSH, HTTPS GUI, SNMP, etc.) |
| `none` | No services |
| Custom list | Specific protocols/ports |

### Recommended Settings

| Self-IP | Recommended Setting | Reason |
|---------|---------------------|--------|
| external-self | `default` | Management access |
| internal-self | `default` | Internal communication |
| ha-self | `default` | HA synchronization |
| Floating IPs | `none` or custom | Only VS traffic |

**Restrict floating IP to virtual server traffic only:**

```bash
tmsh modify net self external-floating allow-service none
```

**Allow specific services:**

```bash
tmsh modify net self external-self allow-service replace-all-with { tcp:443 tcp:22 }
```

---

## Virtual Server IP Addresses

The following IP addresses will be used for virtual servers (configured in later sections):

| Virtual Server | IP Address | Port | VLAN |
|----------------|------------|------|------|
| vs_totp_enroll | 10.1.1.100 | 443 | external |
| vs_totp_api | 10.1.1.101 | 443 | external |
| vs_mfa_portal | 10.1.1.102 | 443 | external |
| vs_totp_admin | 10.1.1.104 | 443 | external |
| vs_totp_api_internal | 10.255.255.255 | 80 | internal |

> **Note:** Virtual server IPs do not require self-IP entries. They are configured directly on the virtual server objects.

### IP Address Planning

Ensure the following when planning IP addresses:

1. **VS IPs must be in the same subnet as a self-IP** — The BIG-IP must have a self-IP on the same VLAN/subnet to respond to ARP requests for VS IPs.

2. **Non-routable internal VS** — The internal API VS (10.255.255.255) should not be reachable from outside the BIG-IP. Choose an address that:
   - Is not routed by your network infrastructure
   - Does not conflict with existing allocations
   - Common choices: `10.255.255.255`, `169.254.x.x`, `127.0.0.x` (with caveats)

3. **Reserve IPs** — Document allocated IPs to prevent conflicts with other services.

---

## Connectivity Testing

### Test External Connectivity

From an external client:

```bash
# Ping BIG-IP external self-IP
ping 10.1.1.1

# Test HTTPS to management (if allowed)
curl -k https://10.1.1.1/tmui/login.jsp
```

### Test Internal Connectivity

From the BIG-IP command line:

```bash
# Verify internal self-IP is active
ping -c 3 10.255.255.254

# Verify internal interface is up
tmsh show net interface 1.2
```

### Test Default Route

```bash
# Ping default gateway
ping -c 3 10.1.1.254

# Trace route to external destination
traceroute 8.8.8.8
```

### Test DNS Resolution

```bash
# Resolve NTP server
nslookup 0.pool.ntp.org

# Resolve AD domain (if applicable)
nslookup corp.example.com
```

---

## Single-Unit vs. HA Configuration

### Single-Unit Deployment

For standalone deployments, configure:

- External VLAN + self-IP
- Internal VLAN + self-IP
- Default route
- No floating IPs required

### HA Deployment

For high availability deployments, configure on **both units**:

- External VLAN + self-IP (unique per unit)
- Internal VLAN + self-IP (unique per unit)
- HA VLAN + self-IP (unique per unit)
- Default route
- Floating IPs (shared, on active unit only)

**Unit 1:**

```bash
tmsh create net self external-self address 10.1.1.1/24 vlan external allow-service default
tmsh create net self internal-self address 10.255.255.254/24 vlan internal allow-service default
tmsh create net self ha-self address 10.1.3.1/24 vlan ha allow-service default
```

**Unit 2:**

```bash
tmsh create net self external-self address 10.1.1.3/24 vlan external allow-service default
tmsh create net self internal-self address 10.255.255.252/24 vlan internal allow-service default
tmsh create net self ha-self address 10.1.3.2/24 vlan ha allow-service default
```

**Floating IPs (configure on one unit, syncs to peer):**

```bash
tmsh create net self external-floating address 10.1.1.2/24 vlan external traffic-group traffic-group-1 allow-service none
```

See [09 - HA Configuration](09-ha-configuration.md) for complete HA setup instructions.

---

## Save Configuration

After completing network configuration:

```bash
tmsh save sys config
```

---

## Troubleshooting

### VLAN Not Showing Traffic

```bash
# Check interface status
tmsh show net interface

# Verify VLAN membership
tmsh show net vlan
```

### Self-IP Not Responding

```bash
# Verify self-IP state
tmsh show net self

# Check port lockdown settings
tmsh list net self <self-ip-name> allow-service
```

### Routing Issues

```bash
# View routing table
netstat -rn

# Test specific route
ping -c 3 <destination>
traceroute <destination>
```

### ARP Issues

```bash
# View ARP table
arp -an

# Clear ARP cache (use carefully)
tmsh delete net arp all
```

---

## Configuration Summary

After completing this section, you should have:

| Component | Single-Unit | HA (per unit) |
|-----------|-------------|---------------|
| External VLAN | ✓ | ✓ |
| Internal VLAN | ✓ | ✓ |
| HA VLAN | — | ✓ |
| External self-IP | ✓ | ✓ |
| Internal self-IP | ✓ | ✓ |
| HA self-IP | — | ✓ |
| External floating IP | — | ✓ |
| Default route | ✓ | ✓ |

---

## Next Steps

Proceed to [03 - SSL Certificates](03-ssl-certificates.md) to create SSL certificates and profiles for the virtual servers.
