# =============================================================================
# iRule: irule_totp_enroll
# Repository: f5-totp-mfa
# License: Apache 2.0
#
# Virtual Server: vs_totp_enroll (10.1.1.100:443)
# Requires: irule_totp_shared attached first on same virtual server
#
# Handles:
#   /public/qrcode.js    — serves QR JavaScript from iFile
#   /enroll              — new enrollment (QR + confirm)
#   /enroll/confirm      — validates enrollment code
#   /enroll/complete     — success page
#   /reenroll            — re-enrollment identity verification
#   /reenroll/verify     — validates current TOTP code
#   /reenroll/newqr      — shows new QR after current code verified
#   /reenroll/confirm    — validates new TOTP code
#   /reenroll/complete   — re-enrollment success page
# =============================================================================

proc enroll_page { label secret otpauth attempts_info } {
    set p "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    append p "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    append p "<title>TOTP Enrollment</title>"
    append p "<style>[call irule_totp_shared::brand_get_css]</style>"
    append p "</head><body><div class=\"card\">[call irule_totp_shared::brand_get_logo]"
    append p "<h1>&#x1F511; TOTP Enrollment</h1>"
    append p "<p class=\"sub\">Multi-Factor Authentication Setup</p>"
    append p "<p class=\"lbl\">Account: $label</p>"
    if { $attempts_info ne "" } {
        append p "<div class=\"warn-bar\">$attempts_info</div>"
    }
    append p "<div class=\"qr\"><canvas id=\"qr\"></canvas></div>"
    append p "<p style=\"color:#8b949e;font-size:.9em\">Scan with your authenticator app</p>"
    append p "<div class=\"secret\"><small>Manual Entry Key:</small>$secret</div>"
    append p "<ol><li>Open your authenticator app</li>"
    append p "<li>Scan the QR code or enter the key manually</li>"
    append p "<li>Enter the 6-digit code below to confirm</li></ol>"
    append p "<form method=\"POST\" action=\"/enroll/confirm\"><div class=\"fg\">"
    append p "<input type=\"text\" name=\"totp_code\" maxlength=\"6\""
    append p " pattern=\"\[0-9\]{6}\" placeholder=\"000000\" required autocomplete=\"off\">"
    append p "</div><button type=\"submit\">Verify and Complete Enrollment</button>"
    append p "</form></div>"
    append p "<script src=\"/public/qrcode.js\"></script>"
    append p "<script>renderQR('qr','$otpauth',6);</script>"
    append p "</body></html>"
    return $p
}

proc enroll_status { title icon bg msg link ltxt } {
    set p "<!DOCTYPE html><html><head><title>$title</title>"
    append p "<style>[call irule_totp_shared::brand_get_status_css]"
    append p " h1{margin-bottom:16px}</style>"
    append p "</head><body><div class=\"c\">[call irule_totp_shared::brand_get_logo]"
    append p "<h1 style=\"color:$bg\">$icon $title</h1>"
    append p "<div class=\"m\" style=\"background:$bg\">$msg</div>"
    if { $link ne "" } { append p "<a href=\"$link\">$ltxt</a>" }
    append p "</div></body></html>"
    return $p
}

proc reenroll_verify_page { username attempts_info } {
    set p "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    append p "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    append p "<title>TOTP Re-enrollment</title>"
    append p "<style>[call irule_totp_shared::brand_get_css]"
    append p " h1{color:#f0883e}"
    append p " button{background:#f0883e}button:hover{background:#d68029}</style>"
    append p "</head><body><div class=\"card\">[call irule_totp_shared::brand_get_logo]"
    append p "<h1>&#x1F504; TOTP Re-enrollment</h1>"
    append p "<p class=\"sub\">Replace your authenticator setup</p>"
    append p "<p class=\"lbl\">Account: $username</p>"
    if { $attempts_info ne "" } {
        append p "<div class=\"warn-bar\">$attempts_info</div>"
    }
    append p "<div class=\"info-box\"><strong>Security verification required</strong><br>"
    append p "Enter a valid code from your <em>current</em> authenticator app"
    append p " before a new QR code can be generated.</div>"
    append p "<form method=\"POST\" action=\"/reenroll/verify\"><div class=\"fg\">"
    append p "<input type=\"text\" name=\"current_code\" maxlength=\"6\""
    append p " pattern=\"\[0-9\]{6}\" placeholder=\"000000\" required autocomplete=\"off\">"
    append p "</div><button type=\"submit\">Verify Current Code</button></form>"
    append p "<a class=\"back\" href=\"/enroll\">&#x2190; Back</a>"
    append p "</div></body></html>"
    return $p
}

proc reenroll_newqr_page { label secret otpauth attempts_info } {
    set p "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    append p "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    append p "<title>New TOTP Setup</title>"
    append p "<style>[call irule_totp_shared::brand_get_css]"
    append p " h1{color:#f0883e}</style>"
    append p "</head><body><div class=\"card\">[call irule_totp_shared::brand_get_logo]"
    append p "<h1>&#x1F504; New TOTP Setup</h1>"
    append p "<p class=\"sub\">Scan the new QR code</p>"
    append p "<p class=\"lbl\">Account: $label</p>"
    if { $attempts_info ne "" } {
        append p "<div class=\"warn-bar\">$attempts_info</div>"
    }
    append p "<div class=\"warn-notice\">&#x26A0; Previous authenticator entry"
    append p " stops working after you confirm the new code.</div>"
    append p "<div class=\"qr\"><canvas id=\"qr\"></canvas></div>"
    append p "<div class=\"secret\"><small>Manual Entry Key:</small>$secret</div>"
    append p "<ol><li>Delete old entry in your authenticator app</li>"
    append p "<li>Scan the new QR code above</li>"
    append p "<li>Enter the 6-digit code from the <strong>new</strong> entry to confirm</li></ol>"
    append p "<form method=\"POST\" action=\"/reenroll/confirm\"><div class=\"fg\">"
    append p "<input type=\"text\" name=\"totp_code\" maxlength=\"6\""
    append p " pattern=\"\[0-9\]{6}\" placeholder=\"000000\" required autocomplete=\"off\">"
    append p "</div><button type=\"submit\">Verify New Code and Complete</button></form></div>"
    append p "<script src=\"/public/qrcode.js\"></script>"
    append p "<script>renderQR('qr','$otpauth',6);</script>"
    append p "</body></html>"
    return $p
}

when HTTP_REQUEST {
    set uri [HTTP::path]
    set method [HTTP::method]

    # Serve QR JavaScript — no session required
    if { $uri eq "/public/qrcode.js" } {
        HTTP::respond 200 content [ifile get "qrcode_js"] \
            "Content-Type" "application/javascript" \
            "Cache-Control" "public, max-age=86400"
        return
    }

    # Wait for APM session before processing enrollment logic
    if { ![ACCESS::session exists] } {
        return
    }

    set username [ACCESS::session data get "session.logon.last.username"]
    set client_ip [IP::client_addr]

    # GET /enroll
    if { $uri eq "/enroll" && $method eq "GET" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        if { [call irule_totp_shared::totp_enroll_ip_is_blocked $client_ip] } {
            set r [table timeout \
                -subtable [call irule_totp_shared::totp_enroll_rate_subtable] \
                -remaining "enroll_ip_${client_ip}"]
            HTTP::respond 200 content [call enroll_status "Too Many Requests" \
                "&#x1F6AB;" "#da3633" "Try again in $r seconds." "" ""] \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
            set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Enrollment Locked" \
                "&#x1F512;" "#da3633" "Too many failures. Try again in $r seconds." "" ""] \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        if { [call irule_totp_shared::totp_is_enrolled $username] } {
            set p "<!DOCTYPE html><html><head><title>Already Enrolled</title>"
            append p "<style>[call irule_totp_shared::brand_get_status_css]"
            append p " h1{color:#1a7f37;margin-bottom:16px}"
            append p " .ok{background:#1a7f37;color:#fff;padding:14px 24px;"
            append p "border-radius:8px;margin:24px 0}</style>"
            append p "</head><body><div class=\"c\">[call irule_totp_shared::brand_get_logo]"
            append p "<h1>&#x1F512; Already Enrolled</h1>"
            append p "<div class=\"ok\">Your account is enrolled in TOTP MFA.</div>"
            append p "<p>Need to replace your authenticator?</p>"
            append p "<a class=\"reenroll\" href=\"/reenroll\">"
            append p "&#x1F504; Re-enroll with New Authenticator</a>"
            append p "</div></body></html>"
            HTTP::respond 200 content $p \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        call irule_totp_shared::totp_enroll_ip_increment $client_ip
        set secret [call irule_totp_shared::totp_generate_secret]
        ACCESS::session data set "session.custom.totp.enroll_secret" $secret
        set issuer [call irule_totp_shared::totp_get_issuer]
        set label "${username}@[call irule_totp_shared::totp_get_issuer]"
        set otpauth "otpauth://totp/${label}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30"
        set ac [call irule_totp_shared::totp_enroll_rate_get_count $username]
        set mx [call irule_totp_shared::totp_enroll_rate_get_max]
        set ai ""
        if { $ac > 0 } { set ai "You have [expr {$mx - $ac}] confirmation attempt(s) remaining." }
        log local0.info "TOTP-ENROLL: Page shown for $username from $client_ip"
        HTTP::respond 200 content [call enroll_page $label $secret $otpauth $ai] \
            "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # POST /enroll/confirm
    if { $uri eq "/enroll/confirm" && $method eq "POST" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        set cl 0
        if { [HTTP::header exists "Content-Length"] } {
            set cl [HTTP::header value "Content-Length"]
        }
        if { $cl > 0 && $cl < 1024 } {
            HTTP::collect $cl
        } else {
            HTTP::redirect "/enroll"
        }
        return
    }

    # GET /enroll/complete
    if { $uri eq "/enroll/complete" } {
        HTTP::respond 200 content [call enroll_status "Enrollment Complete!" \
            "&#x2705;" "#1a7f37" "TOTP MFA is now active." "" ""] \
            "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # GET /reenroll
    if { $uri eq "/reenroll" && $method eq "GET" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        if { ![call irule_totp_shared::totp_is_enrolled $username] } {
            HTTP::redirect "/enroll"
            return
        }
        if { [call irule_totp_shared::totp_enroll_ip_is_blocked $client_ip] } {
            set r [table timeout -subtable [call irule_totp_shared::totp_enroll_rate_subtable] \
                -remaining "enroll_ip_${client_ip}"]
            HTTP::respond 200 content [call enroll_status "Too Many Requests" \
                "&#x1F6AB;" "#da3633" "Try again in $r seconds." "" ""] \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
            set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Re-enrollment Locked" \
                "&#x1F512;" "#da3633" "Too many failures. Try again in $r seconds." "" ""] \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        call irule_totp_shared::totp_enroll_ip_increment $client_ip
        set ac [call irule_totp_shared::totp_enroll_rate_get_count $username]
        set mx [call irule_totp_shared::totp_enroll_rate_get_max]
        set ai ""
        if { $ac > 0 } { set ai "You have [expr {$mx - $ac}] attempt(s) remaining." }
        log local0.info "TOTP-REENROLL: Verify page for $username from $client_ip"
        HTTP::respond 200 content [call reenroll_verify_page $username $ai] \
            "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # POST /reenroll/verify
    if { $uri eq "/reenroll/verify" && $method eq "POST" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        set cl 0
        if { [HTTP::header exists "Content-Length"] } { set cl [HTTP::header value "Content-Length"] }
        if { $cl > 0 && $cl < 1024 } {
            ACCESS::session data set "session.custom.totp.reenroll_step" "verify"
            HTTP::collect $cl
        } else { HTTP::redirect "/reenroll" }
        return
    }

    # GET /reenroll/newqr
    if { $uri eq "/reenroll/newqr" && $method eq "GET" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        if { [ACCESS::session data get "session.custom.totp.reenroll_verified"] ne "yes" } {
            HTTP::redirect "/reenroll"
            return
        }
        if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
            set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Re-enrollment Locked" \
                "&#x1F512;" "#da3633" "Too many failures. Try again in $r seconds." "" ""] \
                "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
            return
        }
        set ns [call irule_totp_shared::totp_generate_secret]
        ACCESS::session data set "session.custom.totp.reenroll_new_secret" $ns
        set issuer [call irule_totp_shared::totp_get_issuer]
        set label "${username}@${issuer}"
        set otpauth "otpauth://totp/${label}?secret=${ns}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30"
        set ac [call irule_totp_shared::totp_enroll_rate_get_count $username]
        set mx [call irule_totp_shared::totp_enroll_rate_get_max]
        set ai ""
        if { $ac > 0 } { set ai "You have [expr {$mx - $ac}] confirmation attempt(s) remaining." }
        log local0.info "TOTP-REENROLL: New QR for $username"
        HTTP::respond 200 content [call reenroll_newqr_page $label $ns $otpauth $ai] \
            "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # POST /reenroll/confirm
    if { $uri eq "/reenroll/confirm" && $method eq "POST" } {
        if { $username eq "" } {
            HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"
            return
        }
        set cl 0
        if { [HTTP::header exists "Content-Length"] } { set cl [HTTP::header value "Content-Length"] }
        if { $cl > 0 && $cl < 1024 } {
            ACCESS::session data set "session.custom.totp.reenroll_step" "confirm"
            HTTP::collect $cl
        } else { HTTP::redirect "/reenroll/newqr" }
        return
    }

    # GET /reenroll/complete
    if { $uri eq "/reenroll/complete" } {
        HTTP::respond 200 content [call enroll_status "Re-enrollment Complete!" \
            "&#x2705;" "#1a7f37" \
            "Your TOTP authenticator has been replaced." "" ""] \
            "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    HTTP::redirect "/enroll"
}

when HTTP_REQUEST_DATA {
    set payload [HTTP::payload]
    set username [ACCESS::session data get "session.logon.last.username"]
    set client_ip [IP::client_addr]
    set rs [ACCESS::session data get "session.custom.totp.reenroll_step"]

    # Re-enrollment: verify current code
    if { $rs eq "verify" } {
        ACCESS::session data set "session.custom.totp.reenroll_step" ""
        if { $username eq "" } { HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"; return }
        if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
            set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Locked" "&#x1F512;" "#da3633" "Try again in $r seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
            return
        }
        set cc ""
        foreach pair [split $payload "&"] {
            set kv [split $pair "="]
            if { [lindex $kv 0] eq "current_code" } { set cc [string trim [lindex $kv 1]] }
        }
        set cc [string map {" " "" "-" ""} $cc]
        if { ![regexp {^[0-9]{6}$} $cc] } {
            call irule_totp_shared::totp_enroll_rate_increment $username
            HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Enter exactly 6 digits." "/reenroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            return
        }
        set an [call irule_totp_shared::totp_enroll_rate_increment $username]
        set enc [call irule_totp_shared::totp_lookup_secret $username]
        if { $enc eq "" } { HTTP::redirect "/enroll"; return }
        set cs [call irule_totp_shared::totp_decrypt_secret $enc]
        if { $cs eq "" } {
            HTTP::respond 200 content [call enroll_status "Error" "&#x274C;" "#da3633" "Internal error. Contact administrator." "/reenroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            return
        }
        if { [call irule_totp_shared::totp_verify_raw $cs $cc] } {
            ACCESS::session data set "session.custom.totp.reenroll_verified" "yes"
            call irule_totp_shared::totp_enroll_rate_reset $username
            log local0.info "TOTP-REENROLL: Current code verified for $username from $client_ip"
            HTTP::redirect "/reenroll/newqr"
        } else {
            set mx [call irule_totp_shared::totp_enroll_rate_get_max]
            set ra [expr { $mx - $an }]; if { $ra < 0 } { set ra 0 }
            log local0.warn "TOTP-REENROLL: Invalid current code $username ($an/$mx) from $client_ip"
            if { $ra > 0 } {
                HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Wrong code. $ra attempt(s) remaining." "/reenroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            } else {
                set lt [call irule_totp_shared::totp_enroll_rate_remaining $username]
                HTTP::respond 200 content [call enroll_status "Re-enrollment Locked" "&#x1F512;" "#da3633" "Try again in $lt seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
            }
        }
        return
    }

    # Re-enrollment: confirm new code
    if { $rs eq "confirm" } {
        ACCESS::session data set "session.custom.totp.reenroll_step" ""
        if { $username eq "" } { HTTP::respond 403 content "Access denied" "Content-Type" "text/plain"; return }
        set ns [ACCESS::session data get "session.custom.totp.reenroll_new_secret"]
        set vf [ACCESS::session data get "session.custom.totp.reenroll_verified"]
        if { $ns eq "" || $vf ne "yes" } {
            HTTP::respond 200 content [call enroll_status "Session Expired" "&#x274C;" "#da3633" "Please start re-enrollment again." "/reenroll" "&#x2190; Start Over"] "Content-Type" "text/html; charset=utf-8"
            return
        }
        if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
            set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Locked" "&#x1F512;" "#da3633" "Try again in $r seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
            return
        }
        set tc ""
        foreach pair [split $payload "&"] {
            set kv [split $pair "="]
            if { [lindex $kv 0] eq "totp_code" } { set tc [string trim [lindex $kv 1]] }
        }
        set tc [string map {" " "" "-" ""} $tc]
        if { ![regexp {^[0-9]{6}$} $tc] } {
            call irule_totp_shared::totp_enroll_rate_increment $username
            HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Enter exactly 6 digits." "/reenroll/newqr" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            return
        }
        set an [call irule_totp_shared::totp_enroll_rate_increment $username]
        if { [call irule_totp_shared::totp_verify_raw $ns $tc] } {
            set encrypted [call irule_totp_shared::totp_encrypt_secret $ns]
            if { $encrypted eq "" } {
                HTTP::respond 200 content [call enroll_status "Error" "&#x274C;" "#da3633" "Internal error." "/reenroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
                return
            }
            call irule_totp_shared::totp_store_secret $username $encrypted
            ACCESS::session data set "session.custom.totp.reenroll_new_secret" ""
            ACCESS::session data set "session.custom.totp.reenroll_verified" ""
            call irule_totp_shared::totp_enroll_rate_reset $username
            log local0.info "TOTP-REENROLL: Complete for $username from $client_ip"
            HTTP::redirect "/reenroll/complete"
        } else {
            set mx [call irule_totp_shared::totp_enroll_rate_get_max]
            set ra [expr { $mx - $an }]; if { $ra < 0 } { set ra 0 }
            log local0.warn "TOTP-REENROLL: Invalid new code $username ($an/$mx) from $client_ip"
            if { $ra > 0 } {
                HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Wrong code. $ra attempt(s) remaining." "/reenroll/newqr" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            } else {
                set lt [call irule_totp_shared::totp_enroll_rate_remaining $username]
                HTTP::respond 200 content [call enroll_status "Re-enrollment Locked" "&#x1F512;" "#da3633" "Try again in $lt seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
            }
        }
        return
    }

    # Original enrollment confirm
    set secret [ACCESS::session data get "session.custom.totp.enroll_secret"]
    if { $username eq "" || $secret eq "" } {
        HTTP::respond 200 content [call enroll_status "Session Expired" "&#x274C;" "#da3633" "Please start enrollment again." "/enroll" "&#x2190; Start Over"] "Content-Type" "text/html; charset=utf-8"
        return
    }
    if { [call irule_totp_shared::totp_enroll_rate_is_blocked $username] } {
        set r [call irule_totp_shared::totp_enroll_rate_remaining $username]
        HTTP::respond 200 content [call enroll_status "Enrollment Locked" "&#x1F512;" "#da3633" "Try again in $r seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
        return
    }
    set tc ""
    foreach pair [split $payload "&"] {
        set kv [split $pair "="]
        if { [lindex $kv 0] eq "totp_code" } { set tc [string trim [lindex $kv 1]] }
    }
    set tc [string map {" " "" "-" ""} $tc]
    if { ![regexp {^[0-9]{6}$} $tc] } {
        call irule_totp_shared::totp_enroll_rate_increment $username
        HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Enter exactly 6 digits." "/enroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
        return
    }
    set an [call irule_totp_shared::totp_enroll_rate_increment $username]
    if { [call irule_totp_shared::totp_verify_raw $secret $tc] } {
        set encrypted [call irule_totp_shared::totp_encrypt_secret $secret]
        if { $encrypted eq "" } {
            HTTP::respond 200 content [call enroll_status "Error" "&#x274C;" "#da3633" "Internal error." "/enroll" "&#x2190; Try Again"] "Content-Type" "text/html; charset=utf-8"
            return
        }
        call irule_totp_shared::totp_store_secret $username $encrypted
        ACCESS::session data set "session.custom.totp.enroll_secret" ""
        call irule_totp_shared::totp_enroll_rate_reset $username
        log local0.info "TOTP-ENROLL: Complete for $username from $client_ip"
        HTTP::redirect "/enroll/complete"
    } else {
        set mx [call irule_totp_shared::totp_enroll_rate_get_max]
        set ra [expr { $mx - $an }]; if { $ra < 0 } { set ra 0 }
        log local0.warn "TOTP-ENROLL: Invalid code $username ($an/$mx) from $client_ip"
        if { $ra > 0 } {
            HTTP::respond 200 content [call enroll_status "Invalid Code" "&#x274C;" "#da3633" "Wrong code. $ra attempt(s) remaining." "/enroll" "&#x2190; Return to Enrollment"] "Content-Type" "text/html; charset=utf-8"
        } else {
            set lt [call irule_totp_shared::totp_enroll_rate_remaining $username]
            HTTP::respond 200 content [call enroll_status "Enrollment Locked" "&#x1F512;" "#da3633" "Try again in $lt seconds." "" ""] "Content-Type" "text/html; charset=utf-8"
        }
    }
}