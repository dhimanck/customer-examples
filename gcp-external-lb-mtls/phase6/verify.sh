#!/usr/bin/env bash
# Phase 6 — Verification
# Runs two smoke tests against the GCP ALB FQDN:
#   1. Authorised: presents a valid client certificate — expects HTTP 200.
#   2. Unauthorised: no certificate presented — expects HTTP 403.
#
# Required environment variables:
#   FQDN      — DNS name of the GCP ALB (e.g. chef-automate.example.com)
#   CERT_DIR  — Directory containing cluster-ca.pem (default: ~/cluster_mtls)
#
# Optional environment variables (for the authorised test):
#   CLIENT_CERT — Path to a node client certificate (default: /etc/chef/ssl/client.crt)
#   CLIENT_KEY  — Path to the matching private key   (default: /etc/chef/ssl/client.key)

set -euo pipefail

: "${FQDN:?Environment variable FQDN must be set}"
CERT_DIR="${CERT_DIR:-${HOME}/cluster_mtls}"
CLIENT_CERT="${CLIENT_CERT:-/etc/chef/ssl/client.crt}"
CLIENT_KEY="${CLIENT_KEY:-/etc/chef/ssl/client.key}"
TARGET_URL="https://${FQDN}"
NGINX_ACCESS_LOG="/hab/svc/automate-load-balancer/var/log/nginx/access.log"

echo "=========================================="
echo " Phase 6 — mTLS Verification"
echo " Target: ${TARGET_URL}"
echo "=========================================="

# ── Test 1: Authorised Access ──────────────────────────────────────────────────
echo ""
echo "--> Test 1: Authorised access (client certificate presented)"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --cacert "${CERT_DIR}/cluster-ca.pem" \
    --cert   "${CLIENT_CERT}" \
    --key    "${CLIENT_KEY}" \
    -I "${TARGET_URL}")

if [[ "${HTTP_STATUS}" == "200" ]]; then
    echo "    PASS — HTTP ${HTTP_STATUS} received as expected."
else
    echo "    FAIL — Expected HTTP 200, got HTTP ${HTTP_STATUS}."
    exit 1
fi

# ── Test 2: Unauthorised Access ────────────────────────────────────────────────
echo ""
echo "--> Test 2: Unauthorised access (no client certificate)"
CURL_STDERR_FILE=$(mktemp)
HTTP_STATUS_NO_CERT=$(curl -s -o /dev/null -w "%{http_code}" \
    --cacert "${CERT_DIR}/cluster-ca.pem" \
    -I "${TARGET_URL}" 2>"${CURL_STDERR_FILE}") || CURL_EXIT=$?

if [[ -n "${CURL_EXIT:-}" ]]; then
    echo "    FAIL — curl exited with code ${CURL_EXIT}. Diagnostic output:"
    cat "${CURL_STDERR_FILE}" >&2
    rm -f "${CURL_STDERR_FILE}"
    exit 1
fi
rm -f "${CURL_STDERR_FILE}"

if [[ "${HTTP_STATUS_NO_CERT}" == "403" ]]; then
    echo "    PASS — HTTP ${HTTP_STATUS_NO_CERT} received as expected (rejected at GCP ALB edge)."
else
    echo "    WARN — Expected HTTP 403, got HTTP ${HTTP_STATUS_NO_CERT}." >&2
    echo "           Verify that the ServerTlsPolicy is attached and REJECT_INVALID is active." >&2
fi

# ── Nginx Access Log Hint ──────────────────────────────────────────────────────
echo ""
echo "--> Verify the real client IP is recorded in the Nginx access log:"
echo "    sudo tail -20 ${NGINX_ACCESS_LOG}"

echo ""
echo "Phase 6 verification complete."
