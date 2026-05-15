#!/usr/bin/env bash
# Phase 6 — Rollback
# Reverts to the pre-mTLS configuration if service is interrupted after
# completing Phases 2–4.
#
# Steps performed:
#   1. Disables X-Forwarded-For trust and mTLS header enforcement in Nginx
#      by patching the Habitat load_balancer service.
#   2. Prints instructions for reverting GCP resources and DNS manually,
#      because those changes carry broader blast-radius and should be
#      confirmed by an operator before execution.
#
# Run on the Bastion / Deployment node.

set -euo pipefail

echo "=========================================="
echo " Phase 6 — Rollback"
echo "=========================================="

# ── Step 1: Disable Nginx header enforcement ───────────────────────────────────
echo ""
echo "--> Disabling X-Forwarded-For trust and mTLS header enforcement in Nginx..."
chef-automate config patch <(cat <<'TOML'
[load_balancer.v1.sys.ngx.http]
  include_x_forwarded_for = false
  extra_config = ""

[cs_nginx.v1.sys.ngx.http]
  extra_config = ""
TOML
)

echo "    Nginx patch applied. Services will reload automatically."

# ── Step 2: Manual GCP rollback guidance ──────────────────────────────────────
echo ""
echo "--> Manual steps required to complete the GCP rollback:"
echo ""
echo "    a) Revert DNS to the internal Load Balancer VIPs (Primary / Secondary)."
echo "       This restores client connectivity while the ALB policy is updated."
echo ""
echo "    b) Detach the ServerTlsPolicy from the HTTPS proxy to restore plain HTTPS:"
echo "       gcloud compute target-https-proxies update \${PROXY_NAME} \\"
echo "           --clear-server-tls-policy"
echo ""
echo "    c) Optionally delete the policy and trust config once traffic is stable:"
echo "       gcloud network-security server-tls-policies delete chef-mtls-policy --location=global"
echo "       gcloud certificate-manager trust-configs delete cluster-frontend-trust --location=global"
echo ""
echo "    d) Optionally delete the backend authentication config and certificate:"
echo "       gcloud network-security backend-authentication-configs delete cluster-backend-auth --location=global"
echo "       gcloud certificate-manager certificates delete gcp-lb-identity --location=global"
echo ""
echo "Phase 6 rollback complete (Nginx reverted). Complete the manual GCP steps above."
