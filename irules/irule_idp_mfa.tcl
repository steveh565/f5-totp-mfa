# =============================================================================
# iRule: irule_idp_mfa
# Repository: f5-totp-mfa
# License: Apache 2.0
#
# Virtual Server: vs_mfa_portal (10.1.1.102:443)
# Requires: irule_totp_shared attached first on same virtual server
#
# Handles the check_totp_enrollment iRule Event agent in the access policy.
# The enrollment redirect is handled natively by the APM Redirect-Enroll
# ending — no iRule redirect logic needed.
# =============================================================================

when ACCESS_POLICY_AGENT_EVENT {
    set aid [ACCESS::policy agent_id]
    set sid [ACCESS::session sid]
    set usr [ACCESS::session data get "session.logon.last.username"]

    if { $aid eq "check_totp_enrollment" } {
        if { $usr eq "" } {
            ACCESS::session data set "session.custom.totp.enrolled" "false"
            return
        }
        if { [call irule_totp_shared::totp_is_enrolled $usr] } {
            ACCESS::session data set "session.custom.totp.enrolled" "true"
            log local0.info "MFA|$sid: $usr enrolled"
        } else {
            ACCESS::session data set "session.custom.totp.enrolled" "false"
            log local0.info "MFA|$sid: $usr NOT enrolled"
        }
    }
}