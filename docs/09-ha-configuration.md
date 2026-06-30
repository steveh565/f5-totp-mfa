# 09 - HA Configuration

This section covers high availability configuration including device trust, device groups, config-sync, traffic groups, and failover behavior specific to the TOTP MFA solution.

---

## HA Architecture Overview

The TOTP MFA solution supports active-standby high availability with automatic failover:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HA Architecture                                      │
└─────────────────────────────────────────────────────────────────────────────┘

                            ┌─────────────────┐
                            │   Clients       │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ Floating IPs    │
                            │ (traffic-group-1)│
                            │                 │
                            │ 10.1.1.100 enroll│
                            │ 10.1.1.101 api   │
                            │ 10.1.1.102 portal│
                            │ 10.1.1.104 admin │
                            └────────┬────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
                    ▼                                 ▼
    ┌───────────────────────────┐   ┌───────────────────────────┐
    │         Unit 1            │   │         Unit 2            │
    │        (Active)           │   │        (Standby)          │
    │                           │   │                           │
    │  Self-IPs:                │   │  Self-IPs:                │
    │   10.1.1.1 (external)     │   │   10.1.1.3 (external)     │
    │   10.255.255.254 (internal)│   │   10.255.255.252 (internal)│
    │   10.1.3.1 (ha)           │   │   10.1.3.2 (ha)           │
    │                           │   │                           │
    │  ┌─────────────────────┐  │   │  ┌─────────────────────┐  │
    │  │ totp_users subtable │  │   │  │ totp_users subtable │  │
    │  │ (active sessions)   │  │   │  │ (empty until        │  │
    │  └─────────────────────┘  │   │  │  failover)          │  │
    │            │              │   │  └─────────────────────┘  │
    │            ▼              │   │            ▲              │
    │  ┌─────────────────────┐  │   │  ┌─────────────────────┐  │
    │  │ totp_secrets_dg     │◄─┼───┼─►│ totp_secrets_dg     │  │
    │  │ totp_config_dg      │  │sync│  │ totp_config_dg      │  │
    │  └─────────────────────┘  │   │  └─────────────────────┘  │
    │                           │   │                           │
    │  /config/totp/*.sh        │   │  /config/totp/*.sh        │
    │  (manual deploy)          │   │  (manual deploy)          │
    │                           │   │                           │
    └───────────────────────────┘   └───────────────────────────┘
                    │                                 │
                    └────────────┬────────────────────┘
                                 │
                            HA VLAN
                          10.1.3.0/24
```

### HA Component Sync Status

| Component | Syncs Automatically | Notes |
|-----------|---------------------|-------|
| totp_secrets_dg | Yes | User secrets synchronized |
| totp_config_dg | Yes | Configuration synchronized |
| iRules | Yes | Code synchronized |
| Virtual Servers | Yes | Configuration synchronized |
| Access Policies | Yes | APM policies synchronized |
| SSL Profiles | Yes | Certificates synchronized |
| totp_users subtable | No | Rebuilt via lazy loading |
| totp_ratelimit subtable | No | Resets on failover |
| Alert Scripts | No | Manual deployment required |
| user_alert.conf | No | Manual configuration required |

---

## Prerequisites

Before configuring HA:

- [ ] Two BIG-IP units with identical provisioning (LTM + APM)
- [ ] Identical software versions on both units
- [ ] Network connectivity between units (HA VLAN)
- [ ] Unique management IPs for each unit
- [ ] Unique self-IPs per unit (external, internal, HA)
- [ ] Floating IPs for virtual servers (shared)
- [ ] TOTP solution fully configured on Unit 1

---

## Network Configuration for HA

### Unit 1 Network Configuration

```bash
# External VLAN and self-IP
tmsh create net vlan external interfaces add { 1.1 { untagged } }
tmsh create net self external-self-unit1 address 10.1.1.1/24 vlan external allow-service default

# Internal VLAN and self-IP
tmsh create net vlan internal interfaces add { 1.2 { untagged } }
tmsh create net self internal-self-unit1 address 10.255.255.254/24 vlan internal allow-service default

# HA VLAN and self-IP
tmsh create net vlan ha interfaces add { 1.3 { untagged } }
tmsh create net self ha-self-unit1 address 10.1.3.1/24 vlan ha allow-service default

# Default route
tmsh create net route default-route gw 10.1.1.254 network default

tmsh save sys config
```

### Unit 2 Network Configuration

```bash
# External VLAN and self-IP
tmsh create net vlan external interfaces add { 1.1 { untagged } }
tmsh create net self external-self-unit2 address 10.1.1.3/24 vlan external allow-service default

# Internal VLAN and self-IP
tmsh create net vlan internal interfaces add { 1.2 { untagged } }
tmsh create net self internal-self-unit2 address 10.255.255.252/24 vlan internal allow-service default

# HA VLAN and self-IP
tmsh create net vlan ha interfaces add { 1.3 { untagged } }
tmsh create net self ha-self-unit2 address 10.1.3.2/24 vlan ha allow-service default

# Default route
tmsh create net route default-route gw 10.1.1.254 network default

tmsh save sys config
```

### Floating IPs (Configure on Unit 1 Only)

Floating IPs are synchronized to Unit 2 via config-sync:

```bash
# External floating IP for virtual servers
tmsh create net self external-floating address 10.1.1.2/24 vlan external traffic-group traffic-group-1 allow-service none

tmsh save sys config
```

---

## Device Trust Configuration

Device trust establishes a secure relationship between HA peers.

### Configure Device Trust (Unit 1)

1. Navigate to: **Device Management → Device Trust → Device Trust Members**

2. Click **Add**

3. Configure:

| Field | Value |
|-------|-------|
| Device IP Address | 10.1.1.3 (Unit 2 management or self-IP) |
| Administrator Username | admin |
| Administrator Password | (Unit 2 admin password) |

4. Click **Retrieve Device Information**

5. Verify device information is correct

6. Click **Device Certificate Matches** (if prompted)

7. Click **Add Device**

### Verify Device Trust

```bash
# On Unit 1
tmsh show cm device-group

# On Unit 2
tmsh show cm device-group
```

Both units should show each other as trusted devices.

### Alternative: tmsh Device Trust

```bash
# On Unit 1, add Unit 2 to trust
tmsh modify cm trust-domain add-device {
    device-ip 10.1.1.3
    device-name bigip2.mfa-demo.local
    username admin
    password "admin-password"
}
```

---

## Device Group Configuration

Device groups define which devices synchronize configuration.

### Create Sync-Failover Device Group

**Via GUI (Unit 1):**

1. Navigate to: **Device Management → Device Groups**

2. Click **Create**

3. Configure:

| Field | Value |
|-------|-------|
| Name | mfa-sync-failover-dg |
| Group Type | Sync-Failover |
| Members | Add both units |

4. Configure Sync Settings:

| Field | Value |
|-------|-------|
| Full Sync | Disabled (recommended) |
| Automatic Sync | Enabled (optional) |
| Network Failover | Enabled |

5. Click **Finished**

**Via tmsh (Unit 1):**

```bash
tmsh create cm device-group mfa-sync-failover-dg {
    type sync-failover
    devices add { bigip1.mfa-demo.local bigip2.mfa-demo.local }
    auto-sync enabled
    full-load-on-sync false
    network-failover enabled
}
```

### Verify Device Group

```bash
tmsh list cm device-group mfa-sync-failover-dg
```

---

## Traffic Group Configuration

Traffic groups control which unit owns floating IPs and virtual servers.

### Default Traffic Group

The default `traffic-group-1` is typically sufficient. Verify configuration:

```bash
tmsh list cm traffic-group traffic-group-1
```

### Verify Traffic Group Assignment

Floating IPs should be assigned to `traffic-group-1`:

```bash
tmsh list net self external-floating traffic-group
```

Expected output:

```
net self external-floating {
    ...
    traffic-group traffic-group-1
    ...
}
```

### Set Failover Order (Optional)

Configure preferred active unit:

```bash
# Make Unit 1 preferred
tmsh modify cm traffic-group traffic-group-1 ha-order { bigip1.mfa-demo.local bigip2.mfa-demo.local }
```

---

## Initial Config Sync

Perform initial synchronization to push configuration from Unit 1 to Unit 2.

### Sync via GUI

1. Navigate to: **Device Management → Overview**

2. Select device group: `mfa-sync-failover-dg`

3. Click **Sync** on Unit 1

4. Select: **Push the selected device group configuration to the group**

5. Click **Sync**

### Sync via tmsh

```bash
# Push configuration from Unit 1 to group
tmsh run cm config-sync to-group mfa-sync-failover-dg
```

### Verify Sync Status

```bash
# Check sync status
tmsh show cm sync-status

# Expected output
# Color: green
# Status: In Sync
```

**Via GUI:**

1. Navigate to: **Device Management → Overview**
2. Verify both devices show green status and "In Sync"

---

## Deploy Alert Scripts to Both Units

Alert scripts are stored in /config and are not synchronized via config-sync.

### Deploy to Unit 1

```bash
# Create directory
mkdir -p /config/totp

# Copy scripts
cp scripts/totp_enroll.sh /config/totp/totp_enroll.sh
cp scripts/totp_unenroll.sh /config/totp/totp_unenroll.sh

# Set permissions
chmod 700 /config/totp/*.sh

# Verify
ls -la /config/totp/
```

### Deploy to Unit 2

```bash
# SSH to Unit 2 or use SCP
ssh root@10.1.1.3 "mkdir -p /config/totp"

scp /config/totp/totp_enroll.sh root@10.1.1.3:/config/totp/
scp /config/totp/totp_unenroll.sh root@10.1.1.3:/config/totp/

ssh root@10.1.1.3 "chmod 700 /config/totp/*.sh"

# Verify
ssh root@10.1.1.3 "ls -la /config/totp/"
```

### Configure user_alert.conf on Both Units

**Unit 1:**

```bash
cat >> /config/user_alert.conf << 'EOF'
alert TOTP_ENROLL_TRIGGER "TOTP_ENROLL_TRIGGER" {
    exec command="/config/totp/totp_enroll.sh"
}
alert TOTP_UNENROLL_TRIGGER "TOTP_UNENROLL_TRIGGER" {
    exec command="/config/totp/totp_unenroll.sh"
}
EOF

bigstart restart alertd
```

**Unit 2:**

```bash
ssh root@10.1.1.3 "cat >> /config/user_alert.conf << 'EOF'
alert TOTP_ENROLL_TRIGGER \"TOTP_ENROLL_TRIGGER\" {
    exec command=\"/config/totp/totp_enroll.sh\"
}
alert TOTP_UNENROLL_TRIGGER \"TOTP_UNENROLL_TRIGGER\" {
    exec command=\"/config/totp/totp_unenroll.sh\"
}
EOF"

ssh root@10.1.1.3 "bigstart restart alertd"
```

### Verify Alert Configuration on Both Units

```bash
# Unit 1
grep "TOTP_" /config/user_alert.conf
bigstart status alertd

# Unit 2
ssh root@10.1.1.3 "grep 'TOTP_' /config/user_alert.conf"
ssh root@10.1.1.3 "bigstart status alertd"
```

---

## Failover Testing

### Test 1: Verify Configuration on Standby

```bash
# SSH to Unit 2
ssh root@10.1.1.3

# Verify data groups synced
tmsh list ltm data-group internal totp_config_dg
tmsh list ltm data-group internal totp_secrets_dg

# Verify virtual servers
tmsh list ltm virtual one-line | grep -E "vs_totp|vs_mfa"

# Verify iRules
tmsh list ltm rule one-line | grep totp

# Verify access policies
tmsh list apm profile access one-line | grep -E "ap_totp|ap_mfa"
```

### Test 2: Manual Failover

**Via GUI:**

1. Navigate to: **Device Management → Traffic Groups**
2. Select `traffic-group-1`
3. Click **Force to Standby**

**Via tmsh (on active unit):**

```bash
tmsh run sys failover standby
```

### Test 3: Verify Services After Failover

After failover to Unit 2:

```bash
# Check traffic group status
tmsh show cm traffic-group traffic-group-1

# Test API health
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"

# Test enrollment check
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/check?username=testuser"
```

### Test 4: User Authentication After Failover

1. Browse to `https://portal.mfa-demo.local`
2. Log in with test credentials
3. Enter TOTP code
4. Verify access granted

> **Note:** Lazy loading rebuilds the subtable from the synced data group. First login after failover may be slightly slower.

### Test 5: Enrollment After Failover

1. Create new test user on active unit
2. Browse to `https://portal.mfa-demo.local`
3. Log in (should redirect to enrollment)
4. Complete enrollment
5. Verify secret persists to data group
6. Verify data group syncs to standby:
   ```bash
   ssh root@10.1.1.1 "tmsh list ltm data-group internal totp_secrets_dg records | grep newuser"
   ```

### Test 6: Fail Back to Original Unit

```bash
# On Unit 2, return to standby
tmsh run sys failover standby

# Verify Unit 1 is active
tmsh show cm traffic-group traffic-group-1
```

---

## Failover Behavior Details

### What Happens During Failover

| Event | Behavior |
|-------|----------|
| Floating IPs | Move to new active unit |
| Active sessions | Interrupted (users must re-authenticate) |
| Subtable data | Lost (rebuilt via lazy loading) |
| Rate limit counters | Reset to zero |
| Data groups | Already synced, immediately available |
| Pending enrollments | May need to restart enrollment |

### Session Persistence

APM sessions are not mirrored by default. Users will need to re-authenticate after failover.

**To enable session mirroring (optional):**

```bash
tmsh modify apm profile access ap_mfa_portal mirror enabled
```

> **Note:** Session mirroring increases HA traffic and memory usage. Evaluate based on your requirements.

### Rate Limit Reset Behavior

Rate limit counters stored in subtables are lost during failover:

| Scenario | Result |
|----------|--------|
| User rate-limited on Unit 1 | Rate limit cleared after failover to Unit 2 |
| Fail back to Unit 1 | Rate limit still cleared (subtable was lost) |

This is a security trade-off. For strict rate limiting, consider:

- External rate limit storage (not covered in this guide)
- Accept reset as acceptable during failover events

---

## Monitoring HA Status

### Check Sync Status

```bash
# Quick status
tmsh show cm sync-status

# Detailed status
tmsh show cm sync-status all-properties
```

### Check Traffic Group Status

```bash
tmsh show cm traffic-group
```

### Check Device Status

```bash
tmsh show cm device
```

### HA Status via GUI

1. Navigate to: **Device Management → Overview**
2. View:
   - Sync status (green = synced)
   - Failover status (active/standby)
   - Device status (online/offline)

### Log Monitoring

```bash
# Watch for HA events
tail -f /var/log/ltm | grep -iE "failover|sync|standby|active"
```

---

## Troubleshooting HA

### Sync Failures

```bash
# Check sync status details
tmsh show cm sync-status all-properties

# View sync errors
tmsh show cm sync-status | grep -i error

# Force full sync (use with caution)
tmsh run cm config-sync force-full-load-push to-group mfa-sync-failover-dg
```

### Device Trust Issues

```bash
# Check trust status
tmsh show cm trust-domain

# Reset trust (last resort)
tmsh delete cm trust-domain all
# Then re-establish trust from scratch
```

### Failover Not Occurring

```bash
# Check failover status
tmsh show sys failover

# Check network failover connectivity
tmsh show cm device | grep -A5 "unicast-address"

# Verify HA VLAN connectivity
ping -c 3 10.1.3.2  # From Unit 1 to Unit 2 HA IP
```

### Configuration Differences

```bash
# Compare configurations (run on each unit)
tmsh list ltm virtual vs_mfa_portal
tmsh list ltm data-group internal totp_config_dg

# If differences found, sync from authoritative unit
tmsh run cm config-sync to-group mfa-sync-failover-dg
```

### Alert Scripts Not Working After Failover

```bash
# Verify scripts exist on new active unit
ls -la /config/totp/

# Verify alert configuration
cat /config/user_alert.conf | grep TOTP

# Verify alertd running
bigstart status alertd

# Test alert trigger
logger -p local0.alert "TOTP_ENROLL_TRIGGER:hatest"
sleep 3
grep "totp_enroll" /var/log/ltm | tail -5
```

---

## HA Maintenance Procedures

### Software Upgrades

1. **Upgrade standby unit first:**
   ```bash
   # On standby unit
   tmsh install sys software image <image-name> volume <volume>
   tmsh reboot volume <volume>
   ```

2. **Verify standby unit after upgrade:**
   ```bash
   tmsh show sys version
   tmsh show cm sync-status
   ```

3. **Failover to upgraded unit:**
   ```bash
   # On old active unit
   tmsh run sys failover standby
   ```

4. **Upgrade original active unit:**
   ```bash
   tmsh install sys software image <image-name> volume <volume>
   tmsh reboot volume <volume>
   ```

5. **Verify sync and functionality**

### Adding/Modifying Configuration

1. **Make changes on active unit**
2. **Sync to standby:**
   ```bash
   tmsh run cm config-sync to-group mfa-sync-failover-dg
   ```
3. **Verify on standby:**
   ```bash
   ssh root@standby "tmsh list <changed-object>"
   ```

### Replacing a Failed Unit

1. **Install BIG-IP on replacement hardware**
2. **Configure basic networking (management, HA VLAN)**
3. **Add to device trust from active unit**
4. **Add to device group**
5. **Sync configuration:**
   ```bash
   tmsh run cm config-sync to-group mfa-sync-failover-dg
   ```
6. **Deploy alert scripts manually**
7. **Configure user_alert.conf**
8. **Restart alertd**

---

## HA Configuration Checklist

### Initial Setup

- [ ] Both units have identical TMOS versions
- [ ] Both units have identical provisioning (LTM + APM)
- [ ] Unique self-IPs configured on each unit
- [ ] HA VLAN configured and tested
- [ ] Device trust established
- [ ] Device group created (sync-failover)
- [ ] Traffic group configured
- [ ] Floating IPs assigned to traffic-group-1
- [ ] Initial config sync completed successfully

### TOTP-Specific

- [ ] Alert scripts deployed to both units
- [ ] user_alert.conf configured on both units
- [ ] alertd running on both units
- [ ] Data groups visible on standby unit
- [ ] Failover tested successfully
- [ ] User authentication works after failover
- [ ] Enrollment works after failover

---

## Save Configuration

```bash
# Save on both units
tmsh save sys config

# Sync after save
tmsh run cm config-sync to-group mfa-sync-failover-dg
```

---

## Configuration Summary

### Network Configuration

| Component | Unit 1 | Unit 2 |
|-----------|--------|--------|
| External Self-IP | 10.1.1.1/24 | 10.1.1.3/24 |
| Internal Self-IP | 10.255.255.254/24 | 10.255.255.252/24 |
| HA Self-IP | 10.1.3.1/24 | 10.1.3.2/24 |
| External Floating | 10.1.1.2/24 | (synced) |

### HA Objects

| Object | Name |
|--------|------|
| Device Group | mfa-sync-failover-dg |
| Traffic Group | traffic-group-1 |
| Sync Type | Sync-Failover |

### Manual Deployments (Both Units)

| Component | Location |
|-----------|----------|
| totp_enroll.sh | /config/totp/totp_enroll.sh |
| totp_unenroll.sh | /config/totp/totp_unenroll.sh |
| Alert config | /config/user_alert.conf |

---

## Next Steps

Proceed to [10 - Administration](10-administration.md) to configure the Admin UI, API key management, and operational procedures.