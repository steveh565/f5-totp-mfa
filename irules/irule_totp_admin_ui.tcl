# =============================================================================
# iRule: irule_totp_admin_ui
# Repository: f5-totp-mfa
# License: Apache 2.0
#
# Virtual Server: vs_totp_admin (10.1.1.104:443)
# Requires: irule_totp_shared attached first on same virtual server
#
# Provides a web UI to view and manage:
#   - totp_users (user secrets subtable)
#   - totp_ratelimit (verification rate limit subtable)
#   - totp_enroll_ratelimit (enrollment rate limit subtable)
#   - totp_secrets_dg (internal data group — enrolled users)
#   - totp_config_dg (configuration data group)
# =============================================================================

proc admin_css {} {
    set css "*, *::before, *::after { box-sizing:border-box; margin:0; padding:0; }"
    append css "body { font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,monospace; background:#0d1117; color:#c9d1d9; padding:20px; max-width:1200px; margin:0 auto; }"
    append css "h1 { color:#58a6ff; margin-bottom:8px; font-size:1.6em; }"
    append css "h2 { color:#58a6ff; margin:24px 0 12px; font-size:1.2em; border-bottom:1px solid #30363d; padding-bottom:6px; }"
    append css "h3 { color:#f0883e; margin:16px 0 8px; font-size:1em; }"
    append css ".nav { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:12px; margin-bottom:20px; }"
    append css ".nav a { color:#58a6ff; text-decoration:none; margin-right:16px; font-size:.95em; }"
    append css ".nav a:hover { text-decoration:underline; }"
    append css "table { width:100%; border-collapse:collapse; margin:12px 0; font-size:.9em; }"
    append css "th { background:#161b22; color:#58a6ff; text-align:left; padding:8px 10px; border:1px solid #30363d; }"
    append css "td { padding:8px 10px; border:1px solid #30363d; word-break:break-all; }"
    append css "tr:nth-child(even) { background:#161b22; }"
    append css ".btn { background:#238636; color:#fff; border:none; padding:4px 12px; border-radius:4px; cursor:pointer; font-size:.85em; }"
    append css ".btn:hover { background:#2ea043; }"
    append css ".btn-danger { background:#da3633; }"
    append css ".btn-danger:hover { background:#f85149; }"
    append css ".btn-warn { background:#f0883e; }"
    append css ".btn-warn:hover { background:#d68029; }"
    append css ".card { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; margin:12px 0; }"
    append css ".stat { display:inline-block; background:#0d1117; border:1px solid #30363d; border-radius:6px; padding:12px 20px; margin:6px; text-align:center; }"
    append css ".stat .num { font-size:1.8em; font-weight:700; color:#58a6ff; display:block; }"
    append css ".stat .lbl { font-size:.8em; color:#8b949e; }"
    append css ".success { background:#1a7f37; color:#fff; padding:8px 16px; border-radius:6px; margin:12px 0; }"
    append css ".error { background:#da3633; color:#fff; padding:8px 16px; border-radius:6px; margin:12px 0; }"
    append css "input\[type=text\] { background:#0d1117; border:1px solid #30363d; color:#c9d1d9; padding:6px 10px; border-radius:4px; font-size:.9em; width:200px; }"
    append css "form { display:inline; }"
    append css ".subtitle { color:#8b949e; margin-bottom:16px; }"
    return $css
}

proc admin_header { title } {
    set p "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>TOTP Admin - $title</title>"
    append p "<style>[call admin_css]</style></head><body>"
    append p "<h1>&#x2699; TOTP Administration</h1>"
    append p "<p class=\"subtitle\">MFA Portal TOTP Secret and Rate Limit Manager</p>"
    append p "<div class=\"nav\">"
    append p "<a href=\"/\">&#x1F4CA; Dashboard</a>"
    append p "<a href=\"/subtable/totp_users\">&#x1F464; Users</a>"
    append p "<a href=\"/subtable/totp_ratelimit\">&#x1F6E1; Verify Rate</a>"
    append p "<a href=\"/subtable/totp_enroll_ratelimit\">&#x1F512; Enroll Rate</a>"
    append p "<a href=\"/datagroup/totp_secrets_dg\">&#x1F511; Secrets DG</a>"
    append p "<a href=\"/datagroup/totp_config_dg\">&#x2699; Config DG</a>"
    append p "</div>"
    return $p
}

proc admin_footer {} {
    return "</body></html>"
}

proc get_subtable_entries { subtable_name } {
    set entries [list]
    foreach key [table keys -subtable $subtable_name] {
        set val [table lookup -subtable $subtable_name $key]
        set remaining "N/A"
        catch { set remaining [table timeout -subtable $subtable_name -remaining $key] }
        lappend entries [list $key $val $remaining]
    }
    return $entries
}

when HTTP_REQUEST {
    set uri [HTTP::path]
    set method [HTTP::method]
    set subtable_name ""

    log local0.info "ADMIN-UI: $method $uri"

    # ---- Dashboard ----
    if { $uri eq "/" && $method eq "GET" } {
        set p [call admin_header "Dashboard"]

        # Gather stats
        set users_count 0
        foreach key [table keys -subtable "totp_users"] { incr users_count }

        set rate_count 0
        set rate_blocked 0
        set mx_rate [call irule_totp_shared::totp_rate_get_max]
        foreach key [table keys -subtable "totp_ratelimit"] {
            incr rate_count
            set v [table lookup -subtable "totp_ratelimit" $key]
            if { $v ne "" && $v >= $mx_rate } { incr rate_blocked }
        }

        set enroll_count 0
        set enroll_blocked 0
        set ip_count 0
        set mx_enroll [call irule_totp_shared::totp_enroll_rate_get_max]
        foreach key [table keys -subtable "totp_enroll_ratelimit"] {
            if { [string match "enroll_ip_*" $key] } {
                incr ip_count
                set v [table lookup -subtable "totp_enroll_ratelimit" $key]
                if { $v ne "" && $v >= [expr { $mx_enroll * 2 }] } { incr enroll_blocked }
            } else {
                incr enroll_count
                set v [table lookup -subtable "totp_enroll_ratelimit" $key]
                if { $v ne "" && $v >= $mx_enroll } { incr enroll_blocked }
            }
        }

        set enrolled_count 0
        foreach key [class names totp_secrets_dg] { incr enrolled_count }

        append p "<h2>System Overview</h2>"
        append p "<div class=\"stat\"><span class=\"num\">$enrolled_count</span><span class=\"lbl\">Enrolled Users (DG)</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$users_count</span><span class=\"lbl\">Users Cache</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$rate_count</span><span class=\"lbl\">Verify Tracked</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$rate_blocked</span><span class=\"lbl\">Verify Blocked</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$enroll_count</span><span class=\"lbl\">Enroll Tracked</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$ip_count</span><span class=\"lbl\">IP Tracked</span></div>"
        append p "<div class=\"stat\"><span class=\"num\">$enroll_blocked</span><span class=\"lbl\">Enroll/IP Blocked</span></div>"

        append p "<h2>Quick Actions</h2>"

        append p "<div class=\"card\">"
        append p "<h3>Reset Rate Limits for User</h3>"
        append p "<form method=\"POST\" action=\"/reset-user\">"
        append p "<input type=\"text\" name=\"username\" placeholder=\"username\" required> "
        append p "<button class=\"btn btn-warn\" type=\"submit\">Reset User</button>"
        append p "</form>"
        append p "</div>"

        append p "<div class=\"card\">"
        append p "<h3>Unenroll User (Remove TOTP)</h3>"
        append p "<form method=\"POST\" action=\"/unenroll-user\">"
        append p "<input type=\"text\" name=\"username\" placeholder=\"username\" required> "
        append p "<button class=\"btn btn-danger\" type=\"submit\">Unenroll</button>"
        append p "</form>"
        append p "</div>"

        append p "<div class=\"card\">"
        append p "<h3>Bulk Clear</h3>"
        append p "<form method=\"POST\" action=\"/clear-subtable\">"
        append p "<input type=\"hidden\" name=\"subtable\" value=\"totp_ratelimit\">"
        append p "<button class=\"btn btn-danger\" type=\"submit\">Clear All Verify Rate Limits</button>"
        append p "</form> "
        append p "<form method=\"POST\" action=\"/clear-subtable\">"
        append p "<input type=\"hidden\" name=\"subtable\" value=\"totp_enroll_ratelimit\">"
        append p "<button class=\"btn btn-danger\" type=\"submit\">Clear All Enroll Rate Limits</button>"
        append p "</form> "
        append p "<form method=\"POST\" action=\"/clear-subtable\">"
        append p "<input type=\"hidden\" name=\"subtable\" value=\"totp_users\">"
        append p "<button class=\"btn btn-danger\" type=\"submit\">Clear Users Cache</button>"
        append p "</form>"
        append p "</div>"

        append p [call admin_footer]
        HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # ---- View subtable ----
    if { [string match "/subtable/*" $uri] && $method eq "GET" } {
        set subtable_name [string range $uri 10 end]
        if { [lsearch -exact {totp_users totp_ratelimit totp_enroll_ratelimit} $subtable_name] == -1 } {
            HTTP::respond 404 content "Unknown subtable" "Content-Type" "text/plain"
            return
        }
        set entries [call get_subtable_entries $subtable_name]

        # Set a human-readable label for the subtable
        set subtable_label $subtable_name
        if { $subtable_name eq "totp_users" } { set subtable_label "Users" }
        if { $subtable_name eq "totp_ratelimit" } { set subtable_label "Verify Rate Limits" }
        if { $subtable_name eq "totp_enroll_ratelimit" } { set subtable_label "Enrollment Rate Limits" }

        set p [call admin_header "Subtable: $subtable_label"]
        append p "<h2>$subtable_label ([llength $entries] entries)</h2>"

        if { [llength $entries] == 0 } {
            append p "<div class=\"card\"><p style=\"color:#8b949e\">No entries in this subtable.</p></div>"
        } else {
            append p "<table><tr><th>Key</th><th>Value</th><th>TTL Remaining (s)</th><th>Action</th></tr>"
            foreach entry $entries {
                set key [lindex $entry 0]
                set val [lindex $entry 1]
                set ttl [lindex $entry 2]
                # Truncate long values for display
                set display_val $val
                if { [string length $display_val] > 60 } {
                    set display_val "[string range $display_val 0 59]..."
                }
                append p "<tr><td>$key</td><td>$display_val</td><td>$ttl</td>"
                append p "<td><form method=\"POST\" action=\"/delete-entry\">"
                append p "<input type=\"hidden\" name=\"subtable\" value=\"$subtable_name\">"
                append p "<input type=\"hidden\" name=\"key\" value=\"$key\">"
                append p "<button class=\"btn btn-danger\" type=\"submit\">Delete</button></form>"
                if { $subtable_name eq "totp_users" } {
                    append p "<form method=\"POST\" action=\"/unenroll-user\">"
                    append p "<input type=\"hidden\" name=\"username\" value=\"$key\">"
                    append p "<button class=\"btn btn-warn\" type=\"submit\">Unenroll</button></form>"
                }
                append p "</td></tr>"
            }
            append p "</table>"
        }

        append p "<div style=\"margin-top:16px\">"
        append p "<form method=\"POST\" action=\"/clear-subtable\">"
        append p "<input type=\"hidden\" name=\"subtable\" value=\"$subtable_name\">"
        append p "<button class=\"btn btn-danger\" type=\"submit\">Clear Entire Subtable</button>"
        append p "</form></div>"

        append p [call admin_footer]
        HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # ---- View data group ----
    if { [string match "/datagroup/*" $uri] && $method eq "GET" } {
        set dg_name [string range $uri 11 end]
        if { [lsearch -exact {totp_secrets_dg totp_config_dg} $dg_name] == -1 } {
            HTTP::respond 404 content "Unknown data group" "Content-Type" "text/plain"
            return
        }
        set p [call admin_header "Data Group: $dg_name"]
        append p "<h2>Data Group: $dg_name</h2>"

        set keys [class names $dg_name]
        set count [llength $keys]
        append p "<p style=\"color:#8b949e\">$count records</p>"

        if { $count == 0 } {
            append p "<div class=\"card\"><p style=\"color:#8b949e\">No records.</p></div>"
        } else {
            append p "<table><tr><th>Key</th><th>Value (truncated)</th>"
            if { $dg_name eq "totp_secrets_dg" } {
                append p "<th>Action</th>"
            }
            append p "</tr>"
            foreach key $keys {
                set val [class match -value $key equals $dg_name]
                set display_val $val
                if { [string length $display_val] > 60 } {
                    set display_val "[string range $display_val 0 59]..."
                }
                append p "<tr><td>$key</td><td>$display_val</td>"
                if { $dg_name eq "totp_secrets_dg" } {
                    append p "<td><form method=\"POST\" action=\"/unenroll-user\">"
                    append p "<input type=\"hidden\" name=\"username\" value=\"$key\">"
                    append p "<button class=\"btn btn-danger\" type=\"submit\">Unenroll</button></form></td>"
                }
                append p "</tr>"
            }
            append p "</table>"
        }
        append p [call admin_footer]
        HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8" "Cache-Control" "no-store"
        return
    }

    # ---- POST actions ----
    if { $method eq "POST" } {
        set cl 0
        catch { set cl [HTTP::header value "Content-Length"] }
        if { $cl > 0 && $cl < 4096 } {
            HTTP::collect $cl
        } else {
            HTTP::redirect "/"
        }
        return
    }

    HTTP::redirect "/"
}

when HTTP_REQUEST_DATA {
    set uri [HTTP::path]
    set payload [HTTP::payload]

    # Parse form data
    array set form {}
    foreach pair [split $payload "&"] {
        set kv [split $pair "="]
        set k [URI::decode [lindex $kv 0]]
        set v [URI::decode [lindex $kv 1]]
        set form($k) $v
    }

    log local0.info "ADMIN-UI: POST $uri"

    # ---- Delete single entry from subtable ----
    if { $uri eq "/delete-entry" } {
        set subtable ""
        set key ""
        catch { set subtable $form(subtable) }
        catch { set key $form(key) }
        if { $subtable ne "" && $key ne "" } {
            if { [lsearch -exact {totp_users totp_ratelimit totp_enroll_ratelimit} $subtable] >= 0 } {
                table delete -subtable $subtable $key
                log local0.notice "ADMIN-UI: Deleted key '$key' from subtable '$subtable'"
                set p [call admin_header "Entry Deleted"]
                append p "<div class=\"success\">Deleted key <strong>$key</strong> from <strong>$subtable</strong></div>"
                append p "<p><a href=\"/subtable/$subtable\">&#x2190; Back to $subtable</a></p>"
                append p [call admin_footer]
                HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8"
                return
            }
        }
        HTTP::respond 400 content "Invalid parameters" "Content-Type" "text/plain"
        return
    }

    # ---- Clear entire subtable ----
    if { $uri eq "/clear-subtable" } {
        set subtable ""
        catch { set subtable $form(subtable) }
        if { $subtable ne "" && [lsearch -exact {totp_users totp_ratelimit totp_enroll_ratelimit} $subtable] >= 0 } {
            set count 0
            foreach key [table keys -subtable $subtable] {
                table delete -subtable $subtable $key
                incr count
            }
            log local0.notice "ADMIN-UI: Cleared $count entries from subtable '$subtable'"
            set p [call admin_header "Subtable Cleared"]
            append p "<div class=\"success\">Cleared <strong>$count</strong> entries from <strong>$subtable</strong></div>"
            append p "<p><a href=\"/\">&#x2190; Back to Dashboard</a></p>"
            append p [call admin_footer]
            HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8"
            return
        }
        HTTP::respond 400 content "Invalid parameters" "Content-Type" "text/plain"
        return
    }

    # ---- Reset user rate limits ----
    if { $uri eq "/reset-user" } {
        set username ""
        catch { set username $form(username) }
        if { $username ne "" } {
            set u [string tolower $username]
            table delete -subtable "totp_ratelimit" "rate_${u}"
            table delete -subtable "totp_enroll_ratelimit" "enroll_${u}"
            log local0.notice "ADMIN-UI: Reset rate limits for '$u'"
            set p [call admin_header "User Reset"]
            append p "<div class=\"success\">Reset all rate limits for <strong>$u</strong></div>"
            append p "<p><a href=\"/\">&#x2190; Back to Dashboard</a></p>"
            append p [call admin_footer]
            HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8"
            return
        }
        HTTP::respond 400 content "Missing username" "Content-Type" "text/plain"
        return
    }

    # ---- Unenroll user ----
    if { $uri eq "/unenroll-user" } {
        set username ""
        catch { set username $form(username) }
        if { $username ne "" } {
            set u [string tolower $username]
            # Remove from runtime subtables
            table delete -subtable "totp_users" $u
            table delete -subtable "totp_ratelimit" "rate_${u}"
            table delete -subtable "totp_enroll_ratelimit" "enroll_${u}"
            # Trigger data group removal via log alert
            log local0.alert "TOTP_UNENROLL_TRIGGER:${u}"
            log local0.notice "ADMIN-UI: Unenrolled '$u' — cleared subtables and triggered DG removal"
            set p [call admin_header "User Unenrolled"]
            append p "<div class=\"success\">Unenrolled <strong>$u</strong> from all subtables and triggered data group removal.</div>"
            append p "<p><a href=\"/\">&#x2190; Back to Dashboard</a></p>"
            append p [call admin_footer]
            HTTP::respond 200 content $p "Content-Type" "text/html; charset=utf-8"
            return
        }
        HTTP::respond 400 content "Missing username" "Content-Type" "text/plain"
        return
    }

    HTTP::redirect "/"
}