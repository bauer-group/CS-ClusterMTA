#!/usr/bin/with-contenv bash
# =============================================================================
# ClusterMTA - Let's Encrypt Certificate Self-Heal (startup trigger)
# =============================================================================
# Runs the certificate reconcile once at container start, AFTER the upstream
# certificate init (21-certificate.sh) and Let's Encrypt init (22-*).
#
# If the previous container life ended with the served cert frozen behind a
# failed renewal (see /opt/clustermta/le-cert-sync.sh for the root cause), this
# re-activates the freshest valid Let's Encrypt certificate before the mail and
# web daemons start -- so they come up serving a valid cert instead of the
# stale one that upstream 21-certificate.sh just copied from /data/ssl.
#
# The heavy lifting (detection, propagation, reload) lives in the shared script
# so the same logic is used by the periodic cron job.
# =============================================================================

set -e

SYNC_SCRIPT="/opt/clustermta/le-cert-sync.sh"

# Ensure the log directory for the periodic cron job exists (persistent volume).
# Non-fatal: a failure here must never suppress the startup reconcile below.
mkdir -p /data/log/clustermta || true

if [ -x "$SYNC_SCRIPT" ]; then
    echo "[ClusterMTA] Reconciling Let's Encrypt certificate at startup..."
    # Never let a cert-sync hiccup block container startup.
    "$SYNC_SCRIPT" || echo "[ClusterMTA] cert-sync reported a non-fatal issue; continuing startup"
else
    echo "[ClusterMTA] WARNING: $SYNC_SCRIPT missing or not executable; skipping cert reconcile"
fi

exit 0
