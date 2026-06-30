# 07 - Persistence and HA

This section covers the data persistence architecture, storage mechanisms, high availability considerations, and disaster recovery procedures for the TOTP MFA solution.

---

## Persistence Architecture Overview

The solution uses a dual-storage architecture to balance performance with persistence:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Persistence Architecture                                │
└─────────────────────────────────────────────────────────────────────────────┘

                              Runtime (Fast)
                    ┌───────────────────────────────┐
                    │       totp_users subtable     │
                    │                               │
                    │  ┌─────────────────────────┐  │
                    │  │ user1 → encrypted_secret│  │
                    │  │ user2 → encrypted_secret│  │
                    │  │ user3 → encrypted_secret│  │
                    │  └─────────────────────────┘  │
                    │                               │
                    │  • In-memory (TMM)            │
                    │  • Microsecond lookups        │
                    │  • Lost on TMM restart        │
                    │  • Indefinite TTL             │
                    └───────────────────────────────┘
                                   │
                                   │ Lazy Load (on first access)
                                   │ Persist (via alert script)
                                   ▼
                             Persistent (Durable)
                    ┌───────────────────────────────┐
                    │     totp_secrets_dg           │
                    │     (Data Group)              │
                    │                               │
                    │  ┌─────────────────────────┐  │
                    │  │ user1 → encrypted_secret│  │
                    │  │ user2 → encrypted_secret│  │
                    │  │ user3 → encrypted_secret│  │
                    │  └─────────────────────────┘  │
                    │                               │
                    │  • Stored in bigip.conf       │
                    │  • Survives restarts          │
                    │  • Config-sync compatible     │
                    │  • HA synchronized            │
                    └───────────────────────────────┘
```

### Storage Comparison

| Aspect | Subtable (totp_users) | Data Group (totp_secrets_dg) |
|--------|----------------------|------------------------------|
| Storage Location | TMM memory | bigip.conf file |
| Access Speed | Microseconds | Milliseconds |
| Survives TMM Restart | No | Yes |
| Survives Reboot | No | Yes |
| HA Sync | No (local only) | Yes (config-sync) |
| Capacity | Limited by memory | Limited by config size |
| Update Method | iRule table commands | tmsh / alert script |

---

## Subtable Storage

### totp_users Subtable

Primary runtime storage for TOTP secrets:

| Property | Value |
|----------|-------|
| Name | totp_users |
| Key | Username |
| Value | Encrypted TOTP secret |
| Timeout | Indefinite |
| Lifetime | Indefinite |

### Subtable Operations

**Set entry (in iRule):**
```tcl
table set -subtable "totp_users" $username $encrypted_secret indefinite indefinite
```

**Get entry (in iRule):**
```tcl
set encrypted_secret [table lookup -subtable "totp_users" $username]
```

**Delete entry (in iRule):**
```tcl
table delete -subtable "totp_users" $username
```

> **Important:** The timeout and lifetime must be set to `indefinite` (not `0`). Setting `0` defaults to 180 seconds, causing entries to expire unexpectedly.

### View Subtable Contents

```bash
# View subtable statistics
tmsh show ltm rule irule_totp_shared stats

# View specific subtable (via iRule debug or API)
# Note: Direct subtable viewing requires iRule access
```

### Subtable Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Memory-only | Lost on TMM restart | Data group persistence |
| Local to unit | Not shared in HA | Config-sync of data group |
| No direct CLI access | Cannot view/edit directly | API endpoints for management |

---

## Data Group Storage

### totp_secrets_dg Data Group

Persistent storage for TOTP secrets:

| Property | Value |
|----------|-------|
| Name | totp_secrets_dg |
| Type | String |
| Key | Username |
| Value | Encrypted TOTP secret |

### View Data Group Contents

```bash
# List all entries
tmsh list ltm data-group internal totp_secrets_dg records

# Count entries
tmsh list ltm data-group internal totp_secrets_dg records | grep -c "{"

# Check specific user
tmsh list ltm data-group internal totp_secrets_dg records | grep -A1 "testuser"
```

### Manual Data Group Operations

**Add entry:**
```bash
tmsh modify ltm data-group internal totp_secrets_dg records add {
    username { data "encrypted_secret_value" }
}
```

**Modify entry:**
```bash
tmsh modify ltm data-group internal totp_secrets_dg records modify {
    username { data "new_encrypted_secret_value" }
}
```

**Delete entry:**
```bash
tmsh modify ltm data-group internal totp_secrets_dg records delete { username }
```

**Delete all entries:**
```bash
tmsh modify ltm data-group internal totp_secrets_dg records none
```

---

## Lazy Loading Mechanism

Secrets are loaded from the data group to the subtable on first access, not at startup.

### Lazy Loading Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Lazy Loading Sequence                                │
└─────────────────────────────────────────────────────────────────────────────┘

  Verification Request          Subtable              Data Group
          │                        │                       │
          │ 1. Lookup user         │                       │
          ├───────────────────────►│                       │
          │                        │                       │
          │ 2. Entry exists?       │                       │
          │◄───────────────────────┤                       │
          │                        │                       │
          │    YES: Use cached     │                       │
          │    secret, verify      │                       │
          │                        │                       │
          │    NO: Continue...     │                       │
          │                        │                       │
          │ 3. Query data group    │                       │
          ├────────────────────────────────────────────────►│
          │                        │                       │
          │ 4. Entry exists?       │                       │
          │◄───────────────────────────────────────────────┤
          │                        │                       │
          │    YES: Cache in       │                       │
          │    subtable            │                       │
          ├───────────────────────►│                       │
          │                        │                       │
          │    Then verify         │                       │
          │                        │                       │
          │    NO: Return          │                       │
          │    "not enrolled"      │                       │
          │                        │                       │
```

### Benefits of Lazy Loading

| Benefit | Description |
|---------|-------------|
| Fast TMM startup | No delay loading thousands of users |
| Memory efficient | Only active users consume subtable memory |
| Self-healing | Automatically recovers after restart |
| HA friendly | Works with config-sync without custom logic |

### Lazy Loading Code Pattern

```tcl
proc get_user_secret { username } {
    # Try subtable first (fast path)
    set secret [table lookup -subtable "totp_users" $username]
    
    if { $secret ne "" } {
        return $secret
    }
    
    # Fall back to data group (slow path)
    set secret [class lookup $username totp_secrets_dg]
    
    if { $secret ne "" } {
        # Cache in subtable for future requests
        table set -subtable "totp_users" $username $secret indefinite indefinite
        return $secret
    }
    
    # User not enrolled
    return ""
}
```

---

## Alert Script Persistence

Alert scripts commit secrets from the subtable to the data group for persistence.

### Persistence Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Alert Script Persistence Flow                           │
└─────────────────────────────────────────────────────────────────────────────┘

  Enrollment            iRule              syslog            alertd           Script
      │                   │                  │                  │                │
      │ 1. Complete       │                  │                  │                │
      │    enrollment     │                  │                  │                │
      ├──────────────────►│                  │                  │                │
      │                   │                  │                  │                │
      │                   │ 2. Store in      │                  │                │
      │                   │    subtable      │                  │                │
      │                   ├────────┐         │                  │                │
      │                   │◄───────┘         │                  │                │
      │                   │                  │                  │                │
      │                   │ 3. Log trigger   │                  │                │
      │                   │    message       │                  │                │
      │                   ├─────────────────►│                  │                │
      │                   │                  │                  │                │
      │                   │                  │ 4. Write to      │                │
      │                   │                  │    /var/log/ltm  │                │
      │                   │                  ├─────────────────►│                │
      │                   │                  │                  │                │
      │                   │                  │                  │ 5. Pattern     │
      │                   │                  │                  │    match       │
      │                   │                  │                  ├───────────────►│
      │                   │                  │                  │                │
      │                   │                  │                  │                │ 6. Query API
      │                   │                  │                  │                │    for secret
      │                   │                  │                  │                ├────┐
      │                   │                  │                  │                │◄───┘
      │                   │                  │                  │                │
      │                   │                  │                  │                │ 7. Update DG
      │                   │                  │                  │                ├────┐
      │                   │                  │                  │                │◄───┘
      │                   │                  │                  │                │
      │                   │                  │                  │                │ 8. Save config
      │                   │                  │                  │                ├────┐
      │                   │                  │                  │                │◄───┘
      │                   │                  │                  │                │
```

### Alert Script Components

| Component | Location | Purpose |
|-----------|----------|---------|
| user_alert.conf | /config/user_alert.conf | Pattern matching rules |
| totp_enroll.sh | /config/totp/totp_enroll.sh | Enrollment persistence |
| totp_unenroll.sh | /config/totp/totp_unenroll.sh | Unenrollment removal |

### Trigger Messages

| Message Pattern | Script Triggered | Action |
|-----------------|------------------|--------|
| `TOTP_ENROLL_TRIGGER:<user>` | totp_enroll.sh | Add/update secret in DG |
| `TOTP_UNENROLL_TRIGGER:<user>` | totp_unenroll.sh | Remove secret from DG |

### Verify Alert System

```bash
# Check alertd status
bigstart status alertd

# View alert configuration
cat /config/user_alert.conf | grep -A2 "TOTP_"

# Test enrollment trigger
logger -p local0.alert "TOTP_ENROLL_TRIGGER:testuser"
sleep 3
tail -20 /var/log/ltm | grep totp

# Test unenrollment trigger
logger -p local0.alert "TOTP_UNENROLL_TRIGGER:testuser"
sleep 3
tail -20 /var/log/ltm | grep totp
```

---

## High Availability Configuration

### HA Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HA Architecture                                      │
└─────────────────────────────────────────────────────────────────────────────┘

        ┌─────────────────────────┐       ┌─────────────────────────┐
        │       Unit 1            │       │       Unit 2            │
        │       (Active)          │       │       (Standby)         │
        │                         │       │                         │
        │  ┌───────────────────┐  │       │  ┌───────────────────┐  │
        │  │ totp_users        │  │       │  │ totp_users        │  │
        │  │ subtable          │  │       │  │ subtable          │  │
        │  │ (runtime cache)   │  │       │  │ (empty until      │  │
        │  └───────────────────┘  │       │  │  failover)        │  │
        │           │             │       │  └───────────────────┘  │
        │           │             │       │           ▲             │
        │           ▼             │       │           │             │
        │  ┌───────────────────┐  │       │  ┌───────────────────┐  │
        │  │ totp_secrets_dg   │◄─┼───────┼─►│ totp_secrets_dg   │  │
        │  │ totp_config_dg    │  │config │  │ totp_config_dg    │  │
        │  │ (data groups)     │  │ sync  │  │ (data groups)     │  │
        │  └───────────────────┘  │       │  └───────────────────┘  │
        │                         │       │                         │
        └─────────────────────────┘       └─────────────────────────┘
                    │                                 │
                    │         Floating IPs            │
                    │    ┌─────────────────────┐      │
                    └───►│ 10.1.1.100 (enroll) │◄─────┘
                         │ 10.1.1.101 (api)    │
                         │ 10.1.1.102 (portal) │
                         │ 10.1.1.104 (admin)  │
                         └─────────────────────┘
```

### What Syncs

| Component | Syncs via Config-Sync | Notes |
|-----------|----------------------|-------|
| totp_secrets_dg | Yes | User secrets persist across failover |
| totp_config_dg | Yes | Configuration shared |
| totp_users subtable | No | Rebuilt via lazy loading |
| totp_ratelimit subtable | No | Rate limits reset on failover |
| iRules | Yes | Code synchronized |
| Virtual Servers | Yes | Configuration synchronized |
| Access Policies | Yes | APM policies synchronized |
| Alert Scripts | No | Must deploy to both units |

### HA Failover Behavior

**Before Failover (Unit 1 Active):**
- Subtable populated with active user sessions
- Rate limit counters tracking attempts
- All traffic handled by Unit 1

**During Failover:**
- Floating IPs move to Unit 2
- Existing sessions may be interrupted
- Subtable on Unit 2 is empty

**After Failover (Unit 2 Active):**
- Users authenticate normally
- Lazy loading populates subtable from synced DG
- Rate limit counters start fresh (security trade-off)

### Deploy Alert Scripts to Both Units

Alert scripts are not synchronized via config-sync. Deploy manually to each unit:

**Unit 1:**
```bash
mkdir -p /config/totp
scp scripts/totp_enroll.sh root@unit1.mfa-demo.local:/config/totp/
scp scripts/totp_unenroll.sh root@unit1.mfa-demo.local:/config/totp/
ssh root@unit1.mfa-demo.local "chmod 700 /config/totp/*.sh"
```

**Unit 2:**
```bash
mkdir -p /config/totp
scp scripts/totp_enroll.sh root@unit2.mfa-demo.local:/config/totp/
scp scripts/totp_unenroll.sh root@unit2.mfa-demo.local:/config/totp/
ssh root@unit2.mfa-demo.local "chmod 700 /config/totp/*.sh"
```

### Configure user_alert.conf on Both Units

**Unit 1 and Unit 2:**
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

### Verify HA Sync

```bash
# Check sync status
tmsh show cm sync-status

# Force sync (if needed)
tmsh run cm config-sync to-group <device-group-name>

# Verify data group on standby
ssh root@unit2.mfa-demo.local "tmsh list ltm data-group internal totp_secrets_dg records"
```

---

## Disaster Recovery

### Backup Procedures

**Export Data Groups:**
```bash
# Export secrets data group
tmsh list ltm data-group internal totp_secrets_dg > /var/tmp/totp_secrets_dg_backup.txt

# Export config data group
tmsh list ltm data-group internal totp_config_dg > /var/tmp/totp_config_dg_backup.txt

# Copy off-system
scp /var/tmp/totp_*_backup.txt admin@backup-server:/backups/bigip/
```

**Export Encryption Key (Critical):**
```bash
# Extract encryption key (store securely!)
tmsh list ltm data-group internal totp_config_dg records | grep -A1 "encryption_key"
```

> **Warning:** Without the encryption key, all stored secrets are unrecoverable. Store the encryption key in a secure vault.

**Full UCS Backup:**
```bash
tmsh save sys ucs /var/local/ucs/totp-mfa-backup.ucs
scp /var/local/ucs/totp-mfa-backup.ucs admin@backup-server:/backups/bigip/
```

### Recovery Procedures

**Restore Data Groups:**
```bash
# If data groups are lost, restore from backup
# First, recreate empty data groups
tmsh create ltm data-group internal totp_secrets_dg type string
tmsh create ltm data-group internal totp_config_dg type string

# Then import records (manual process from backup file)
# Example for single user:
tmsh modify ltm data-group internal totp_secrets_dg records add {
    username { data "encrypted_secret" }
}
```

**Restore from UCS:**
```bash
tmsh load sys ucs /var/local/ucs/totp-mfa-backup.ucs
```

**Repopulate Subtable After Recovery:**
```bash
# Force reload from data group
API_KEY=$(tmsh list ltm data-group internal totp_config_dg records | grep -A1 "api_key" | grep "data" | awk '{print $2}' | tr -d '"')

curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"
```

### TMM Restart Recovery

After a TMM restart, the subtable is empty but the system self-heals:

1. **Immediate:** Subtable is empty
2. **First user access:** Lazy loading fetches from DG
3. **Subsequent access:** Served from subtable cache
4. **No manual intervention required**

### Full System Recovery Checklist

- [ ] Restore bigip.conf or UCS backup
- [ ] Verify totp_config_dg exists with encryption key
- [ ] Verify totp_secrets_dg exists with user records
- [ ] Deploy alert scripts to /config/totp/
- [ ] Configure /config/user_alert.conf
- [ ] Restart alertd: `bigstart restart alertd`
- [ ] Test enrollment flow
- [ ] Test verification flow
- [ ] Verify HA sync (if applicable)

---

## Monitoring and Maintenance

### Health Checks

**API Health:**
```bash
curl -sk -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/health"
```

**Enrolled User Count:**
```bash
tmsh list ltm data-group internal totp_secrets_dg records | grep -c "{"
```

**Alert System:**
```bash
bigstart status alertd
```

### Log Monitoring

**Watch for persistence events:**
```bash
tail -f /var/log/ltm | grep -E "totp_enroll|totp_unenroll|TOTP_"
```

**Key log patterns:**

| Pattern | Meaning | Action |
|---------|---------|--------|
| `totp_enroll: Committed secret` | Successful persistence | Normal |
| `totp_enroll: Failed to retrieve` | API error | Check API VS |
| `totp_unenroll: Removed` | Successful removal | Normal |
| `TOTP_ENROLL_TRIGGER` | Trigger fired | Normal |

### Periodic Maintenance

**Weekly:**
- Verify backup procedures
- Check log files for errors
- Monitor enrolled user growth

**Monthly:**
- Test disaster recovery procedure
- Review rate limit configurations
- Audit enrolled users

**Quarterly:**
- Rotate API key
- Review encryption key storage
- Test HA failover

---

## Capacity Planning

### Subtable Sizing

| Users | Estimated Memory | Notes |
|-------|------------------|-------|
| 100 | ~50 KB | Minimal impact |
| 1,000 | ~500 KB | Typical small deployment |
| 10,000 | ~5 MB | Medium deployment |
| 100,000 | ~50 MB | Large deployment |

### Data Group Sizing

| Users | Config Size Impact | Notes |
|-------|-------------------|-------|
| 100 | ~10 KB | Negligible |
| 1,000 | ~100 KB | Minimal |
| 10,000 | ~1 MB | Monitor config size |
| 100,000 | ~10 MB | Consider external storage |

### Scaling Considerations

For very large deployments (>100,000 users), consider:

- External database for secret storage
- Custom iRule modifications for external lookups
- Sharding across multiple BIG-IP pairs
- APM session variable caching

---

## Troubleshooting

### Secrets Not Persisting

```bash
# Check alertd
bigstart status alertd

# Check alert config
cat /config/user_alert.conf | grep TOTP

# Check script permissions
ls -la /config/totp/

# Test alert trigger manually
logger -p local0.alert "TOTP_ENROLL_TRIGGER:debuguser"
sleep 3
grep "totp_enroll" /var/log/ltm | tail -5
```

### HA Sync Issues

```bash
# Check sync status
tmsh show cm sync-status

# Check device group
tmsh list cm device-group

# Force sync
tmsh run cm config-sync to-group <device-group-name>

# Verify on standby
ssh standby "tmsh list ltm data-group internal totp_secrets_dg"
```

### Subtable Not Populating

```bash
# Check data group has entries
tmsh list ltm data-group internal totp_secrets_dg records

# Force population via API
curl -sk -X POST -H "X-API-Key: $API_KEY" \
    "https://totp-api.mfa-demo.local:443/api/v1/populate-table"

# Check for iRule errors
tail -f /var/log/ltm | grep -i error
```

### Recovery After Encryption Key Loss

If the encryption key is lost:

1. **All existing secrets are unrecoverable**
2. Generate new encryption key
3. Clear totp_secrets_dg: `tmsh modify ltm data-group internal totp_secrets_dg records none`
4. All users must re-enroll

> **Prevention:** Always maintain secure backups of the encryption key.

---

## Save Configuration

```bash
tmsh save sys config
```

---

## Configuration Summary

### Storage Architecture

| Component | Type | Persistence | HA Sync |
|-----------|------|-------------|---------|
| totp_users | Subtable | No (memory) | No |
| totp_ratelimit | Subtable | No (memory) | No |
| totp_enroll_ratelimit | Subtable | No (memory) | No |
| totp_secrets_dg | Data Group | Yes (config) | Yes |
| totp_config_dg | Data Group | Yes (config) | Yes |

### Alert Scripts

| Script | Location | Trigger |
|--------|----------|---------|
| totp_enroll.sh | /config/totp/ | TOTP_ENROLL_TRIGGER |
| totp_unenroll.sh | /config/totp/ | TOTP_UNENROLL_TRIGGER |

---

## Next Steps

Proceed to [08 - MFA Portal](08-mfa-portal.md) to configure the MFA portal virtual server, HTTP AAA integration, access policy macros, and webtop resources.