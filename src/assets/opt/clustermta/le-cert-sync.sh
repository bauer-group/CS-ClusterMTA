#!/usr/bin/env bash
# =============================================================================
# ClusterMTA - Let's Encrypt Certificate Self-Heal / Reconcile
# =============================================================================
# Keeps the *served* certificate store (/etc/ssl/*) in sync with the freshest
# valid Let's Encrypt certificate in /data/ssl/letsencrypt/<domain>/.
#
# WHY THIS EXISTS
# ---------------
# Upstream Poste.io renews certificates in App\Base\Handler\LeHandler::renew():
#
#   1. signDomains()                        -> writes fresh cert.pem / fullchain.pem
#                                              / chain.pem / private.pem into
#                                              /data/ssl/letsencrypt/<domain>/
#   2. copy fullchain/chain/private         -> /tmp/server.crt|ca.crt|server.key
#   3. alert->renewOk()  (sends an e-mail)  <-- CAN THROW
#   4. restartAllAfterCertificateChange()   -> runs 21-certificate.sh which copies
#                                              the certs into /etc/ssl and reloads
#                                              the mail/web daemons
#
# All four steps live in ONE try/catch. If step 3 throws (alerts address unset,
# SMTP/TLS error while sending, ...), step 4 is skipped: the fresh certificate
# sits in /data/ssl/letsencrypt/<domain>/ but /etc/ssl/* (what nginx, dovecot
# and haraka actually serve) is never updated. Worse, the next daily renewal is
# short-circuited by the "issued < 14 days ago" guard reading the *fresh* source
# cert, so the activation is never retried -- the served cert stays frozen until
# it expires.
#
# This script decouples "obtain" from "activate": it independently detects when
# the served cert drifts from the freshest valid LE cert and re-propagates +
# reloads. It is idempotent and only acts on real drift, so it is safe to run
# both at container start and on a short interval via cron.
#
# Invocation:
#   le-cert-sync.sh            # normal run
#   le-cert-sync.sh --cron     # identical; label used only for log context
#
# Runs as root (needs to write /etc/ssl and signal s6 services).
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (paths mirror the upstream Poste.io layout)
# -----------------------------------------------------------------------------
LE_DIR="/data/ssl/letsencrypt"          # lescript_certs_path (services_base.yaml)
DATA_SSL="/data/ssl"                    # persistent cert store
ETC_SSL="/etc/ssl"                      # live cert store read by the daemons
SERVER_INI="/data/server.ini"           # holds [lets_encrypt] cert_domains
LOCK_FILE="/run/clustermta-le-sync.lock"
LOG_TAG="ClusterMTA cert-sync"

log() { echo "[$LOG_TAG] $*"; }

# -----------------------------------------------------------------------------
# Certificate helpers
# -----------------------------------------------------------------------------

# SHA-256 fingerprint of the FIRST certificate in a PEM file (the leaf).
# Empty output => unreadable / not a certificate.
cert_fingerprint() {
    openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true
}

# notBefore (issuance date) of the leaf certificate as a Unix epoch (0 =>
# unreadable). Used as the "newer" proxy: a more recently issued cert wins.
cert_startdate_epoch() {
    local start
    start=$(openssl x509 -in "$1" -noout -startdate 2>/dev/null | cut -d= -f2) || true
    [ -n "${start:-}" ] && date -d "$start" +%s 2>/dev/null || echo 0
}

# True (0) if the leaf certificate is already expired.
cert_is_expired() {
    ! openssl x509 -in "$1" -checkend 0 -noout >/dev/null 2>&1
}

# True (0) if the certificate is self-signed (issuer == subject) -- i.e. the
# stock Poste.io placeholder (O=Poste.io, ~10 year validity) rather than a
# genuinely CA-issued certificate. Such a placeholder must always yield to a
# valid Let's Encrypt certificate regardless of its (far-future) expiry.
cert_is_selfsigned() {
    local subj iss
    subj=$(openssl x509 -in "$1" -noout -subject 2>/dev/null) || return 1
    iss=$(openssl x509 -in "$1" -noout -issuer 2>/dev/null) || return 1
    # Strip the leading "subject="/"issuer=" label, then compare the DNs.
    [ -n "$subj" ] && [ "${subj#subject=}" = "${iss#issuer=}" ]
}

# -----------------------------------------------------------------------------
# Determine the active Let's Encrypt domain (the directory renew() writes to).
#
# Authoritative source: the first token of the *active* (non-commented)
# `cert_domains = "..."` line in /data/server.ini. renew() uses names()[0] as
# the certificate directory name, so this matches exactly. Returns empty when
# Let's Encrypt is not configured (self-signed / behind a TLS-terminating
# proxy) -- in which case this script is a no-op.
# -----------------------------------------------------------------------------
detect_domain() {
    [ -f "$SERVER_INI" ] || return 0
    local line value
    line=$(grep -E '^[[:space:]]*cert_domains[[:space:]]*=' "$SERVER_INI" 2>/dev/null | head -1) || true
    [ -n "${line:-}" ] || return 0
    # cert_domains = "primary.example.com alt1.example.com" -> primary.example.com
    value=${line#*=}
    value=${value//\"/}
    # shellcheck disable=SC2086
    set -- $value
    echo "${1:-}"
}

# -----------------------------------------------------------------------------
# Reload a daemon only if its s6 service is actually up (so the same code path
# works at container start, when services are not running yet, and at runtime).
#   $1 = service directory   $2 = s6-svc signal flag (-h reload, -i restart)
# -----------------------------------------------------------------------------
reload_if_up() {
    local svc_dir="$1" flag="$2"
    [ -d "$svc_dir" ] || return 0
    if s6-svstat "$svc_dir" 2>/dev/null | grep -q '^up'; then
        log "  reloading $(basename "$svc_dir") ($flag)"
        s6-svc "$flag" "$svc_dir" || log "  WARN: failed to signal $(basename "$svc_dir")"
    fi
}

# -----------------------------------------------------------------------------
# Propagate the freshest LE cert into the served store and reload the daemons.
# Deterministically derived from /data/ssl/letsencrypt/<domain>/ -- never from
# the volatile /tmp/*.crt left behind by a partially-failed renew().
#
# File mapping matches upstream renew() exactly, so the result is byte-for-byte
# what a fully successful renewal would have produced:
#   server.crt <- fullchain.pem   ca.crt <- chain.pem   server.key <- private.pem
# -----------------------------------------------------------------------------
propagate() {
    local le_path="$1"

    log "propagating fresh certificate into $DATA_SSL and $ETC_SSL"

    # 1) Refresh the persistent store (/data/ssl) so a plain container restart
    #    (which runs upstream 21-certificate.sh) also serves the fresh cert.
    install -m 0644 "$le_path/fullchain.pem" "$DATA_SSL/server.crt"
    install -m 0644 "$le_path/chain.pem"     "$DATA_SSL/ca.crt"
    install -m 0600 "$le_path/private.pem"   "$DATA_SSL/server.key"
    chown -R mail:mail "$DATA_SSL"

    # 2) Refresh the live store (/etc/ssl) read by nginx / dovecot / haraka.
    #    Mirrors 21-certificate.sh: server-combined.crt = server.crt + ca.crt.
    #    Published atomically via a temp file + rename so that (a) no daemon ever
    #    reads a half-written file and (b) a symlink planted in /etc/ssl by a
    #    hostile in-container process is REPLACED, not followed (defence in depth
    #    on top of the Dockerfile hardening /etc/ssl to 0755).
    publish() {                     # $1 = filename under /etc/ssl; content on stdin
        local dst="$ETC_SSL/$1" tmp
        tmp=$(mktemp "$ETC_SSL/.$1.XXXXXX")
        cat > "$tmp"
        chmod 0644 "$tmp"
        mv -f "$tmp" "$dst"
    }
    publish ca.crt     < "$DATA_SSL/ca.crt"
    publish server.crt < "$DATA_SSL/server.crt"
    publish server.key < "$DATA_SSL/server.key"
    { cat "$DATA_SSL/server.crt"; printf '\n'; cat "$DATA_SSL/ca.crt"; } | publish server-combined.crt

    # 3) Reload the daemons (only those already running). haraka has no graceful
    #    reload -> restart (-i); nginx reloads on SIGHUP (-h); dovecot via doveadm.
    reload_if_up "/var/run/s6/services/nginx"             "-h"
    reload_if_up "/var/run/s6/services/haraka-smtp"       "-i"
    reload_if_up "/var/run/s6/services/haraka-submission" "-i"
    if [ -d "/var/run/s6/services/dovecot" ] && \
       s6-svstat "/var/run/s6/services/dovecot" 2>/dev/null | grep -q '^up'; then
        log "  reloading dovecot (doveadm reload)"
        doveadm reload 2>/dev/null || log "  WARN: doveadm reload failed"
    fi

    log "certificate activated"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local mode="${1:-}"
    [ "$mode" = "--cron" ] && LOG_TAG="$LOG_TAG cron"

    # --- Gate 1: Let's Encrypt must be configured -----------------------------
    local domain
    domain=$(detect_domain)
    if [ -z "$domain" ]; then
        # LE disabled (self-signed / proxy). Nothing to reconcile.
        exit 0
    fi

    local le_path="$LE_DIR/$domain"
    # --- Gate 2: a complete issued cert set must exist ------------------------
    if [ ! -f "$le_path/cert.pem" ] || [ ! -f "$le_path/fullchain.pem" ] || \
       [ ! -f "$le_path/chain.pem" ] || [ ! -f "$le_path/private.pem" ]; then
        # LE configured but not issued yet -> let upstream do the first issuance.
        exit 0
    fi

    # --- Gate 3: never activate an already-expired source cert ----------------
    if cert_is_expired "$le_path/cert.pem"; then
        log "source certificate for '$domain' is expired; leaving current cert in place (upstream renewal required)"
        exit 0
    fi

    # --- Drift detection ------------------------------------------------------
    local src_fp served_fp
    src_fp=$(cert_fingerprint "$le_path/cert.pem")
    [ -n "$src_fp" ] || { log "WARN: cannot read source certificate; aborting"; exit 0; }

    served_fp=""
    [ -f "$ETC_SSL/server.crt" ] && served_fp=$(cert_fingerprint "$ETC_SSL/server.crt")

    if [ "$src_fp" = "$served_fp" ]; then
        # Already in sync -- the common case, stay silent to avoid log spam.
        exit 0
    fi

    # The leaves differ. Activate the (valid, non-expired) LE cert UNLESS the
    # served cert is a genuinely CA-issued certificate that was issued MORE
    # recently than the LE source -- that protects a deliberately uploaded
    # newer cert from being downgraded.
    #
    # "Newer" is measured by notBefore (issuance), NOT notAfter (expiry): the
    # stock Poste.io self-signed placeholder is valid for ~10 years, so an
    # expiry comparison would keep that browser-untrusted placeholder forever
    # in place of a fresh 90-day LE cert -- exactly the first-issuance case
    # this self-heal exists to fix. A self-signed served cert therefore always
    # yields to the LE source.
    if [ -n "$served_fp" ] && ! cert_is_selfsigned "$ETC_SSL/server.crt"; then
        local src_start served_start
        src_start=$(cert_startdate_epoch "$le_path/cert.pem")
        served_start=$(cert_startdate_epoch "$ETC_SSL/server.crt")
        if [ "$src_start" -lt "$served_start" ]; then
            log "served certificate is CA-issued and newer than the LE source; not downgrading"
            exit 0
        fi
    fi

    log "drift detected for '$domain' (served fp: ${served_fp:-none}, source fp: $src_fp) -- re-activating"
    propagate "$le_path"
}

# Serialize concurrent runs (start-up trigger vs. cron) if flock is available.
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -n 9 || { echo "[$LOG_TAG] another run holds the lock; skipping"; exit 0; }
fi

main "$@"
