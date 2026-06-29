# =============================================================================
# iRule: irule_totp_shared
# Repository: f5-totp-mfa
# License: Apache 2.0
#
# Purpose: Shared procedures for TOTP operations.
# Attach FIRST on: vs_totp_enroll, vs_totp_verify, vs_totp_verify_internal,
#                  vs_mfa_portal, vs_totp_admin
#
# Design: All configuration is read from the totp_config_dg data group
# at call time. No static:: variables are used in procs. All proc-to-proc
# calls use the irule_totp_shared:: prefix for cross-iRule compatibility.
#
# TMOS Tcl 8.5 Compatibility:
#   - No expr 0b (binary literals)
#   - No scan %b or format %b (binary format specifiers)
#   - No format %ll (64-bit format specifiers)
#   - No $x in {list} or $x ni {list} operators
#   - Uses bits_to_int/int_to_bits procs for binary conversion
#   - Uses binary format II for 64-bit counter encoding
# =============================================================================

# ---- Data Group and Subtable Names ----
proc totp_config_dg_name {} { return "totp_config_dg" }
proc totp_users_subtable {} { return "totp_users" }
proc totp_rate_subtable {} { return "totp_ratelimit" }
proc totp_enroll_rate_subtable {} { return "totp_enroll_ratelimit" }
proc totp_secrets_dg_name {} { return "totp_secrets_dg" }

# ---- Binary Conversion Helpers (TMOS Tcl 8.5 compatible) ----
proc bits_to_int { bitstring } {
    set result 0
    foreach bit [split $bitstring ""] {
        set result [expr { ($result << 1) | $bit }]
    }
    return $result
}

proc int_to_bits { value width } {
    set bits ""
    for { set i [expr { $width - 1 }] } { $i >= 0 } { incr i -1 } {
        if { $value & (1 << $i) } {
            append bits "1"
        } else {
            append bits "0"
        }
    }
    return $bits
}

# ---- Config Lookups ----
proc totp_get_api_key {} {
    set k [class match -value "api_key" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $k eq "" } { log local0.err "TOTP: api_key not found" }
    return $k
}

proc totp_get_encryption_key {} {
    set k [class match -value "encryption_key" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $k eq "" } { log local0.err "TOTP: encryption_key not found" }
    return $k
}

proc totp_get_issuer {} {
    set v [class match -value "issuer" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v eq "" } { return "mfa-demo" }
    return $v
}

proc totp_get_period {} {
    set v [class match -value "totp_period" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 30
}

proc totp_get_window {} {
    set v [class match -value "totp_window" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 1
}

proc totp_rate_get_max {} {
    set v [class match -value "rate_max_attempts" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 5
}

proc totp_rate_get_window {} {
    set v [class match -value "rate_window_seconds" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 300
}

proc totp_enroll_rate_get_max {} {
    set v [class match -value "enroll_rate_max_attempts" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 3
}

proc totp_enroll_rate_get_window {} {
    set v [class match -value "enroll_rate_window_seconds" equals [call irule_totp_shared::totp_config_dg_name]]
    if { $v ne "" } { return $v }
    return 600
}

# ---- Secret Lookup (table only — DG is for persistence) ----
proc totp_lookup_secret { username } {
    set u [string tolower $username]
    set subtable [call irule_totp_shared::totp_users_subtable]
    set cached [table lookup -subtable $subtable $u]
    if { $cached ne "" } { return $cached }
    set dg_val [class match -value $u equals [call irule_totp_shared::totp_secrets_dg_name]]
    if { $dg_val ne "" } {
        table set -subtable $subtable $u $dg_val indefinite indefinite
        log local0.info "TOTP: Lazy-loaded $u from DG to table"
        return $dg_val
    }
    return ""
}

proc totp_is_enrolled { username } {
    if { [call irule_totp_shared::totp_lookup_secret $username] ne "" } { return 1 }
    return 0
}

proc totp_store_secret { username encrypted_secret } {
    set u [string tolower $username]
    table set -subtable [call irule_totp_shared::totp_users_subtable] $u $encrypted_secret indefinite indefinite
    log local0.alert "TOTP_ENROLL_TRIGGER:${u}"
    log local0.info "TOTP: Stored $u in table (indefinite), triggered commit"
}

proc totp_populate_table_from_dg {} {
    set dg_name [call irule_totp_shared::totp_secrets_dg_name]
    set subtable [call irule_totp_shared::totp_users_subtable]
    set count 0
    foreach key [class names $dg_name] {
        set val [class match -value $key equals $dg_name]
        if { $val ne "" } {
            table set -subtable $subtable $key $val indefinite indefinite
            incr count
        }
    }
    log local0.info "TOTP: Populated table from DG — $count records loaded"
    return $count
}

# ---- Encryption / Decryption ----
proc totp_encrypt_secret { plaintext } {
    set k [call irule_totp_shared::totp_get_encryption_key]
    if { $k eq "" } { return "" }
    if { [catch {
        set e [CRYPTO::encrypt -alg aes-256-ecb -key [b64decode $k] $plaintext]
    } err] } {
        log local0.err "TOTP: Encrypt failed: $err"
        return ""
    }
    return $e
}

proc totp_decrypt_secret { ciphertext } {
    set k [call irule_totp_shared::totp_get_encryption_key]
    if { $k eq "" } { return "" }
    if { [catch {
        set d [CRYPTO::decrypt -alg aes-256-ecb -key [b64decode $k] $ciphertext]
    } err] } {
        log local0.err "TOTP: Decrypt failed: $err"
        return ""
    }
    return $d
}

# ---- Base32 Encode / Decode ----
proc totp_base32_decode { b32_string } {
    set alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    set bits ""
    set clean [string trimright [string toupper $b32_string] "="]
    foreach char [split $clean ""] {
        set idx [string first $char $alphabet]
        if { $idx < 0 } { continue }
        append bits [call irule_totp_shared::int_to_bits $idx 5]
    }
    set bytes ""
    set bitlen [string length $bits]
    for { set i 0 } { [expr { $i + 7 }] < $bitlen } { incr i 8 } {
        set byte_bits [string range $bits $i [expr { $i + 7 }]]
        set byte_val [call irule_totp_shared::bits_to_int $byte_bits]
        append bytes [format %c $byte_val]
    }
    return $bytes
}

proc totp_bytes_to_base32 { bytes } {
    set alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    set b32 ""
    binary scan $bytes B* bits
    set bitlen [string length $bits]
    set pad [expr { (5 - ($bitlen % 5)) % 5 }]
    append bits [string repeat "0" $pad]
    for { set i 0 } { $i < [string length $bits] } { incr i 5 } {
        set chunk [string range $bits $i [expr { $i + 4 }]]
        set idx [call irule_totp_shared::bits_to_int $chunk]
        append b32 [string index $alphabet $idx]
    }
    return $b32
}

proc totp_generate_secret {} {
    set rb [AES::key 256]
    return [call irule_totp_shared::totp_bytes_to_base32 [string range $rb 0 19]]
}

# ---- HOTP / TOTP ----
proc totp_compute_hotp { secret_bytes counter } {
    set high [expr { ($counter >> 32) & 0xFFFFFFFF }]
    set low  [expr { $counter & 0xFFFFFFFF }]
    set cb [binary format II $high $low]
    set hmac [CRYPTO::sign -alg hmac-sha1 -key $secret_bytes $cb]
    binary scan $hmac H* hx
    set last_two [string range $hx end-1 end]
    scan $last_two %x lb
    set off [expr { $lb & 0x0f }]
    set s [expr { $off * 2 }]
    set dbc_hex [string range $hx $s [expr { $s + 7 }]]
    scan $dbc_hex %x dbc
    return [format %06d [expr { ($dbc & 0x7fffffff) % 1000000 }]]
}

proc totp_verify_raw { secret_b32 code } {
    set sb [call irule_totp_shared::totp_base32_decode $secret_b32]
    set now [clock seconds]
    set period [call irule_totp_shared::totp_get_period]
    set window [call irule_totp_shared::totp_get_window]
    for { set i [expr { -1 * $window }] } { $i <= $window } { incr i } {
        set ctr [expr { ($now + ($i * $period)) / $period }]
        if { $code eq [call irule_totp_shared::totp_compute_hotp $sb $ctr] } { return 1 }
    }
    return 0
}

# ---- Verification Rate Limiting ----
proc totp_rate_is_blocked { username } {
    set u [string tolower $username]
    set key "rate_${u}"
    set max [call irule_totp_shared::totp_rate_get_max]
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c ne "" && $c >= $max } {
        set r [table timeout -subtable $subtable -remaining $key]
        log local0.warn "TOTP_RATE:BLOCKED:${u}:attempts=${c},max=${max},lockout_remaining=${r}s"
        return 1
    }
    return 0
}

proc totp_rate_increment { username } {
    set u [string tolower $username]
    set key "rate_${u}"
    set max [call irule_totp_shared::totp_rate_get_max]
    set window [call irule_totp_shared::totp_rate_get_window]
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c eq "" } {
        table set -subtable $subtable $key 1 $window $window
        log local0.info "TOTP_RATE:ATTEMPT:${u}:attempt=1,max=${max},window=${window}s"
        return 1
    }
    set nc [expr { $c + 1 }]
    set r [table timeout -subtable $subtable -remaining $key]
    if { $r < 1 } { set r $window }
    table set -subtable $subtable $key $nc $r $r
    if { $nc >= $max } {
        log local0.alert "TOTP_RATE:LOCKOUT:${u}:attempts=${nc},max=${max},locked_for=${r}s,client=[IP::client_addr]"
    } else {
        log local0.info "TOTP_RATE:ATTEMPT:${u}:attempt=${nc},max=${max},remaining_attempts=[expr {$max - $nc}]"
    }
    return $nc
}

proc totp_rate_reset { username } {
    set u [string tolower $username]
    set key "rate_${u}"
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    table delete -subtable $subtable $key
    if { $c ne "" && $c > 0 } {
        log local0.info "TOTP_RATE:RESET:${u}:previous_attempts=${c}"
    }
}

proc totp_rate_admin_reset { username admin_info } {
    set u [string tolower $username]
    set key "rate_${u}"
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    table delete -subtable $subtable $key
    log local0.notice "TOTP_RATE:ADMIN:${u}:previous_attempts=${c},admin=${admin_info}"
}

proc totp_rate_remaining { username } {
    set u [string tolower $username]
    set key "rate_${u}"
    set max [call irule_totp_shared::totp_rate_get_max]
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c ne "" && $c >= $max } {
        return [table timeout -subtable $subtable -remaining $key]
    }
    return 0
}

proc totp_rate_get_count { username } {
    set u [string tolower $username]
    set subtable [call irule_totp_shared::totp_rate_subtable]
    set c [table lookup -subtable $subtable "rate_${u}"]
    if { $c eq "" } { return 0 }
    return $c
}

# ---- Enrollment Rate Limiting ----
proc totp_enroll_rate_is_blocked { username } {
    set u [string tolower $username]
    set key "enroll_${u}"
    set max [call irule_totp_shared::totp_enroll_rate_get_max]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c ne "" && $c >= $max } {
        set r [table timeout -subtable $subtable -remaining $key]
        log local0.warn "TOTP_ENROLL_RATE:BLOCKED:${u}:attempts=${c},max=${max},lockout_remaining=${r}s"
        return 1
    }
    return 0
}

proc totp_enroll_rate_increment { username } {
    set u [string tolower $username]
    set key "enroll_${u}"
    set max [call irule_totp_shared::totp_enroll_rate_get_max]
    set window [call irule_totp_shared::totp_enroll_rate_get_window]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c eq "" } {
        table set -subtable $subtable $key 1 $window $window
        log local0.info "TOTP_ENROLL_RATE:ATTEMPT:${u}:attempt=1,max=${max},window=${window}s"
        return 1
    }
    set nc [expr { $c + 1 }]
    set r [table timeout -subtable $subtable -remaining $key]
    if { $r < 1 } { set r $window }
    table set -subtable $subtable $key $nc $r $r
    if { $nc >= $max } {
        log local0.alert "TOTP_ENROLL_RATE:LOCKOUT:${u}:attempts=${nc},max=${max},locked_for=${r}s,client=[IP::client_addr]"
    } else {
        log local0.info "TOTP_ENROLL_RATE:ATTEMPT:${u}:attempt=${nc},max=${max},remaining_attempts=[expr {$max - $nc}]"
    }
    return $nc
}

proc totp_enroll_rate_reset { username } {
    set u [string tolower $username]
    set key "enroll_${u}"
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    table delete -subtable $subtable $key
    if { $c ne "" && $c > 0 } {
        log local0.info "TOTP_ENROLL_RATE:RESET:${u}:previous_attempts=${c}"
    }
}

proc totp_enroll_rate_admin_reset { username admin_info } {
    set u [string tolower $username]
    set key "enroll_${u}"
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    table delete -subtable $subtable $key
    log local0.notice "TOTP_ENROLL_RATE:ADMIN:${u}:previous_attempts=${c},admin=${admin_info}"
}

proc totp_enroll_rate_remaining { username } {
    set u [string tolower $username]
    set key "enroll_${u}"
    set max [call irule_totp_shared::totp_enroll_rate_get_max]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c ne "" && $c >= $max } {
        return [table timeout -subtable $subtable -remaining $key]
    }
    return 0
}

proc totp_enroll_rate_get_count { username } {
    set u [string tolower $username]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable "enroll_${u}"]
    if { $c eq "" } { return 0 }
    return $c
}

# ---- IP-Based Enrollment Rate Limiting ----
proc totp_enroll_ip_is_blocked { client_ip } {
    set key "enroll_ip_${client_ip}"
    set max [expr { [call irule_totp_shared::totp_enroll_rate_get_max] * 2 }]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c ne "" && $c >= $max } {
        set r [table timeout -subtable $subtable -remaining $key]
        log local0.warn "TOTP_ENROLL_RATE:IP_BLOCKED:${client_ip}:attempts=${c},max=${max},lockout_remaining=${r}s"
        return 1
    }
    return 0
}

proc totp_enroll_ip_increment { client_ip } {
    set key "enroll_ip_${client_ip}"
    set max [expr { [call irule_totp_shared::totp_enroll_rate_get_max] * 2 }]
    set window [call irule_totp_shared::totp_enroll_rate_get_window]
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    set c [table lookup -subtable $subtable $key]
    if { $c eq "" } {
        table set -subtable $subtable $key 1 $window $window
        return 1
    }
    set nc [expr { $c + 1 }]
    set r [table timeout -subtable $subtable -remaining $key]
    if { $r < 1 } { set r $window }
    table set -subtable $subtable $key $nc $r $r
    if { $nc >= $max } {
        log local0.alert "TOTP_ENROLL_RATE:IP_LOCKOUT:${client_ip}:attempts=${nc},max=${max},locked_for=${r}s"
    }
    return $nc
}

# ---- Bulk Rate Reset ----
proc totp_rate_bulk_reset { admin_info } {
    set vc 0; set ec 0; set ic 0
    set rate_st [call irule_totp_shared::totp_rate_subtable]
    set enroll_st [call irule_totp_shared::totp_enroll_rate_subtable]
    foreach key [table keys -subtable $rate_st] {
        table delete -subtable $rate_st $key; incr vc
    }
    foreach key [table keys -subtable $enroll_st] {
        if { [string match "enroll_ip_*" $key] } { incr ic } else { incr ec }
        table delete -subtable $enroll_st $key
    }
    set t [expr { $vc + $ec + $ic }]
    log local0.notice "TOTP_RATE:BULK_RESET:verify=${vc},enroll=${ec},ip=${ic},total=${t},admin=${admin_info}"
    return [list $vc $ec $ic $t]
}

proc totp_rate_bulk_reset_verify { admin_info } {
    set c 0
    set subtable [call irule_totp_shared::totp_rate_subtable]
    foreach key [table keys -subtable $subtable] {
        table delete -subtable $subtable $key; incr c
    }
    log local0.notice "TOTP_RATE:BULK_RESET_VERIFY:count=${c},admin=${admin_info}"
    return $c
}

proc totp_rate_bulk_reset_enroll { admin_info } {
    set uc 0; set ic 0
    set subtable [call irule_totp_shared::totp_enroll_rate_subtable]
    foreach key [table keys -subtable $subtable] {
        if { [string match "enroll_ip_*" $key] } { incr ic } else { incr uc }
        table delete -subtable $subtable $key
    }
    set t [expr { $uc + $ic }]
    log local0.notice "TOTP_RATE:BULK_RESET_ENROLL:users=${uc},ips=${ic},total=${t},admin=${admin_info}"
    return [list $uc $ic $t]
}

proc totp_rate_summary {} {
    set vt 0; set vb 0; set et 0; set eb 0; set it 0; set ib 0
    set mv [call irule_totp_shared::totp_rate_get_max]
    set me [call irule_totp_shared::totp_enroll_rate_get_max]
    set mi [expr { $me * 2 }]
    set rate_st [call irule_totp_shared::totp_rate_subtable]
    set enroll_st [call irule_totp_shared::totp_enroll_rate_subtable]
    foreach key [table keys -subtable $rate_st] {
        incr vt
        set c [table lookup -subtable $rate_st $key]
        if { $c ne "" && $c >= $mv } { incr vb }
    }
    foreach key [table keys -subtable $enroll_st] {
        set c [table lookup -subtable $enroll_st $key]
        if { [string match "enroll_ip_*" $key] } {
            incr it
            if { $c ne "" && $c >= $mi } { incr ib }
        } else {
            incr et
            if { $c ne "" && $c >= $me } { incr eb }
        }
    }
    return [list $vt $vb $et $eb $it $ib]
}

# ---- Rate-Limited TOTP Verification ----
proc totp_verify_code_rated { username code } {
    set u [string tolower $username]
    if { [call irule_totp_shared::totp_rate_is_blocked $username] } { return "rate_limited" }
    set an [call irule_totp_shared::totp_rate_increment $username]
    set enc [call irule_totp_shared::totp_lookup_secret $username]
    if { $enc eq "" } {
        log local0.info "TOTP_RATE:ATTEMPT:${u}:result=not_enrolled"
        return "not_enrolled"
    }
    set sec [call irule_totp_shared::totp_decrypt_secret $enc]
    if { $sec eq "" } {
        log local0.err "TOTP_RATE:ATTEMPT:${u}:result=decrypt_error"
        return "decrypt_error"
    }
    if { [call irule_totp_shared::totp_verify_raw $sec $code] } {
        call irule_totp_shared::totp_rate_reset $username
        log local0.info "TOTP_RATE:ATTEMPT:${u}:result=success,attempt=${an}"
        return "success"
    }
    set mx [call irule_totp_shared::totp_rate_get_max]
    set ra [expr { $mx - $an }]
    if { $ra < 0 } { set ra 0 }
    log local0.warn "TOTP_RATE:ATTEMPT:${u}:result=invalid_code,attempt=${an},remaining_attempts=${ra}"
    return "invalid_code"
}

# ---- Branding (centralized) ----

proc brand_get_css {} {
    set css "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}"
    append css "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; display:flex;justify-content:center;align-items:center;min-height:100vh; background:#0d1117;color:#c9d1d9}"
    append css ".card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:40px;max-width:520px;width:92%;text-align:center;box-shadow:0 8px 24px rgba(0,0,0,.4)}"
    append css "h1{color:#58a6ff;margin-bottom:8px;font-size:1.5em}"
    append css ".sub{color:#8b949e;margin-bottom:24px}"
    append css ".lbl{color:#58a6ff;font-weight:700;margin:8px 0}"
    append css ".qr{background:#fff;display:inline-block;padding:16px;border-radius:8px;margin:20px 0}"
    append css ".secret{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:14px;margin:14px 0;font-family:monospace;font-size:1.1em;letter-spacing:3px;word-break:break-all;color:#f0883e}"
    append css ".secret small{color:#8b949e;display:block;margin-bottom:8px;letter-spacing:normal;font-family:sans-serif}"
    append css "ol{text-align:left;background:#0d1117;border-radius:8px;padding:14px 14px 14px 32px;margin:14px 0}"
    append css "ol li{margin:6px 0;color:#8b949e}"
    append css ".fg{margin:16px 0}"
    append css "input\[type=text\]{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;padding:12px 16px;border-radius:8px;font-size:1.2em;text-align:center;letter-spacing:8px;width:200px}"
    append css "input:focus{outline:none;border-color:#58a6ff}"
    append css "button{background:#238636;color:#fff;border:none;padding:12px 32px;border-radius:8px;font-size:1em;cursor:pointer;margin-top:8px}"
    append css "button:hover{background:#2ea043}"
    append css ".warn-bar{background:#da3633;color:#fff;padding:8px 16px;border-radius:6px;margin:10px 0;font-size:.9em}"
    append css ".warn-notice{background:#f0883e;color:#fff;padding:10px 16px;border-radius:6px;margin:14px 0;font-size:.9em}"
    append css ".info-box{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:14px;margin:14px 0;text-align:left;color:#8b949e;line-height:1.6}"
    append css ".back{display:block;margin-top:16px;color:#58a6ff;text-decoration:none;font-size:.95em}"
    return $css
}

proc brand_get_logo {} {
    return ""
}

proc brand_get_status_css {} {
    set css "body{font-family:sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#0d1117;color:#c9d1d9}"
    append css ".c{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:48px;max-width:480px;text-align:center}"
    append css ".m{color:#fff;padding:14px 24px;border-radius:8px;margin:24px 0}"
    append css "a{color:#58a6ff;text-decoration:none;font-size:1.1em}"
    append css "p{color:#8b949e;line-height:1.6}"
    append css ".reenroll{color:#f0883e;border:1px solid #f0883e;padding:10px 24px;border-radius:8px;display:inline-block;margin-top:16px}"
    return $css
}