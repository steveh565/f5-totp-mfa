# =============================================================================
# iRule: irule_totp_verify
# Repository: f5-totp-mfa
# License: Apache 2.0
#
# Virtual Servers: vs_totp_verify (10.1.1.101:443) — external, SSL
#                  vs_totp_verify_internal (10.255.255.255:80) — internal
# Requires: irule_totp_shared attached first on same virtual server
# =============================================================================

proc verify_json { status body } {
    HTTP::respond $status content $body \
        "Content-Type" "application/json" \
        "Cache-Control" "no-store" \
        "X-Content-Type-Options" "nosniff"
}

proc verify_json_retry { status body ra } {
    HTTP::respond $status content $body \
        "Content-Type" "application/json" \
        "Cache-Control" "no-store" \
        "X-Content-Type-Options" "nosniff" \
        "Retry-After" $ra
}

proc verify_dispatch_result { result username } {
    set ul [string tolower $username]
    switch $result {
        "success" {
            call verify_json 200 "\{\"result\":\"success\",\"username\":\"$ul\"\}"
        }
        "not_enrolled" {
            call verify_json 401 "\{\"result\":\"failure\",\"reason\":\"Not enrolled\",\"username\":\"$ul\"\}"
        }
        "decrypt_error" {
            call verify_json 500 "\{\"result\":\"error\",\"reason\":\"Internal error\"\}"
        }
        "invalid_code" {
            set mx [call irule_totp_shared::totp_rate_get_max]
            set ra [expr { $mx - [call irule_totp_shared::totp_rate_get_count $username] }]
            if { $ra < 0 } { set ra 0 }
            call verify_json 401 "\{\"result\":\"failure\",\"reason\":\"Invalid TOTP code\",\"username\":\"$ul\",\"remaining_attempts\":$ra\}"
        }
        "rate_limited" {
            set r [call irule_totp_shared::totp_rate_remaining $username]
            call verify_json_retry 429 "\{\"result\":\"error\",\"reason\":\"Too many failed attempts\",\"username\":\"$ul\",\"retry_after\":$r\}" $r
        }
    }
}

when HTTP_REQUEST {
    set path [HTTP::path]
    set meth [HTTP::method]

    set ek [call irule_totp_shared::totp_get_api_key]
    set pk [HTTP::header value "X-API-Key"]
    if { $ek eq "" } {
        call verify_json 500 "\{\"result\":\"error\",\"reason\":\"Server misconfiguration\"\}"
        event disable all; return
    }
    if { $pk ne $ek } {
        call verify_json 403 "\{\"result\":\"error\",\"reason\":\"Forbidden\"\}"
        event disable all; return
    }

    if { $path eq "/api/v1/health" } {
        call verify_json 200 "\{\"result\":\"ok\"\}"
        event disable all; return
    }

    if { $path eq "/api/v1/check" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        set ul [string tolower $u]
        if { [call irule_totp_shared::totp_is_enrolled $u] } {
            call verify_json 200 "\{\"result\":\"enrolled\",\"username\":\"$ul\"\}"
        } else {
            call verify_json 200 "\{\"result\":\"not_enrolled\",\"username\":\"$ul\"\}"
        }
        event disable all; return
    }

    if { $path eq "/api/v1/status" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        set ul [string tolower $u]
        set c [call irule_totp_shared::totp_rate_get_count $u]
        set b [call irule_totp_shared::totp_rate_is_blocked $u]
        set r [call irule_totp_shared::totp_rate_remaining $u]
        set mx [call irule_totp_shared::totp_rate_get_max]
        call verify_json 200 "\{\"result\":\"ok\",\"username\":\"$ul\",\"attempts\":$c,\"max_attempts\":$mx,\"blocked\":$b,\"lockout_remaining\":$r\}"
        event disable all; return
    }

    if { $path eq "/api/v1/enroll-status" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        set ul [string tolower $u]
        set c [call irule_totp_shared::totp_enroll_rate_get_count $u]
        set mx [call irule_totp_shared::totp_enroll_rate_get_max]
        set b [call irule_totp_shared::totp_enroll_rate_is_blocked $u]
        set r [call irule_totp_shared::totp_enroll_rate_remaining $u]
        call verify_json 200 "\{\"result\":\"ok\",\"username\":\"$ul\",\"enroll_attempts\":$c,\"enroll_max\":$mx,\"enroll_blocked\":$b,\"enroll_lockout_remaining\":$r\}"
        event disable all; return
    }

    if { $path eq "/api/v1/rate-summary" } {
        set s [call irule_totp_shared::totp_rate_summary]
        call verify_json 200 "\{\"result\":\"ok\",\"verify\":\{\"tracked\":[lindex $s 0],\"blocked\":[lindex $s 1]\},\"enroll\":\{\"tracked\":[lindex $s 2],\"blocked\":[lindex $s 3]\},\"ip\":\{\"tracked\":[lindex $s 4],\"blocked\":[lindex $s 5]\}\}"
        event disable all; return
    }

    if { $path eq "/api/v1/rate-reset" && $meth eq "POST" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        call irule_totp_shared::totp_rate_admin_reset $u "api_client=[IP::client_addr]"
        call verify_json 200 "\{\"result\":\"ok\",\"username\":\"[string tolower $u]\",\"message\":\"Rate limit reset\"\}"
        event disable all; return
    }

    if { $path eq "/api/v1/enroll-rate-reset" && $meth eq "POST" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        call irule_totp_shared::totp_enroll_rate_admin_reset $u "api_client=[IP::client_addr]"
        call verify_json 200 "\{\"result\":\"ok\",\"username\":\"[string tolower $u]\",\"message\":\"Enrollment rate limit reset\"\}"
        event disable all; return
    }

    if { $path eq "/api/v1/rate-reset-all" && $meth eq "POST" } {
        set c [call irule_totp_shared::totp_rate_bulk_reset "api_client=[IP::client_addr]"]
        call verify_json 200 "\{\"result\":\"ok\",\"message\":\"All rate limits cleared\",\"cleared\":\{\"verify\":[lindex $c 0],\"enroll\":[lindex $c 1],\"ip\":[lindex $c 2],\"total\":[lindex $c 3]\}\}"
        event disable all; return
    }

    if { $path eq "/api/v1/rate-reset-verify-all" && $meth eq "POST" } {
        set c [call irule_totp_shared::totp_rate_bulk_reset_verify "api_client=[IP::client_addr]"]
        call verify_json 200 "\{\"result\":\"ok\",\"message\":\"Verification rate limits cleared\",\"cleared\":$c\}"
        event disable all; return
    }

    if { $path eq "/api/v1/rate-reset-enroll-all" && $meth eq "POST" } {
        set c [call irule_totp_shared::totp_rate_bulk_reset_enroll "api_client=[IP::client_addr]"]
        call verify_json 200 "\{\"result\":\"ok\",\"message\":\"Enrollment rate limits cleared\",\"cleared\":\{\"users\":[lindex $c 0],\"ips\":[lindex $c 1],\"total\":[lindex $c 2]\}\}"
        event disable all; return
    }

    if { $path eq "/api/v1/populate-table" && $meth eq "POST" } {
        set count [call irule_totp_shared::totp_populate_table_from_dg]
        call verify_json 200 "\{\"result\":\"ok\",\"message\":\"Table populated from data group\",\"records\":$count\}"
        event disable all; return
    }

    if { $path eq "/api/v1/export-secret" && $meth eq "GET" } {
        set u [URI::query [HTTP::uri] "username"]
        if { $u eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username\"\}"; event disable all; return }
        set ul [string tolower $u]
        set cached [table lookup -subtable [call irule_totp_shared::totp_users_subtable] $ul]
        if { $cached ne "" } {
            call verify_json 200 "\{\"result\":\"ok\",\"username\":\"$ul\",\"secret\":\"$cached\"\}"
        } else {
            call verify_json 404 "\{\"result\":\"error\",\"reason\":\"Not in cache\",\"username\":\"$ul\"\}"
        }
        event disable all; return
    }

    if { $path eq "/api/v1/verify" && $meth eq "GET" } {
        set u [URI::query [HTTP::uri] "username"]
        set c [URI::query [HTTP::uri] "code"]
        if { $u eq "" || $c eq "" } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username or code\"\}"; event disable all; return }
        set c [string map {" " "" "-" ""} [string trim $c]]
        if { ![regexp {^[0-9]{6}$} $c] } { call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Code must be 6 digits\"\}"; event disable all; return }
        call verify_dispatch_result [call irule_totp_shared::totp_verify_code_rated $u $c] $u
        event disable all; return
    }

    if { $path eq "/api/v1/verify" && $meth eq "POST" } {
        set cl 0
        catch { set cl [HTTP::header value "Content-Length"] }
        if { $cl > 0 && $cl < 4096 } {
            HTTP::collect $cl
        } else {
            call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Invalid Content-Length\"\}"
            event disable all
        }
        return
    }

    call verify_json 404 "\{\"result\":\"error\",\"reason\":\"Not found\"\}"
    event disable all
}

when HTTP_REQUEST_DATA {
    set payload [HTTP::payload]
    set ct [HTTP::header value "Content-Type"]
    set u ""; set c ""

    if { [string match -nocase "*json*" $ct] } {
        regexp {"username"\s*:\s*"([^"]*)"} $payload -> u
        regexp {"code"\s*:\s*"([^"]*)"} $payload -> c
    } else {
        foreach pair [split $payload "&"] {
            set kv [split $pair "="]
            switch -- [URI::decode [lindex $kv 0]] {
                "username" { set u [URI::decode [lindex $kv 1]] }
                "code"     { set c [URI::decode [lindex $kv 1]] }
            }
        }
    }

    if { $u eq "" || $c eq "" } {
        call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Missing username or code\"\}"
        return
    }
    set c [string map {" " "" "-" ""} [string trim $c]]
    if { ![regexp {^[0-9]{6}$} $c] } {
        call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Code must be 6 digits\"\}"
        return
    }
    if { ![regexp {^[a-zA-Z0-9._@-]+$} $u] } {
        call verify_json 400 "\{\"result\":\"error\",\"reason\":\"Invalid username\"\}"
        return
    }
    call verify_dispatch_result [call irule_totp_shared::totp_verify_code_rated $u $c] $u
}