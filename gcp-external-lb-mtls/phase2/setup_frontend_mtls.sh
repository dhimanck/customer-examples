#!/usr/bin/env bash
# Phase 2 — Hop 1: Frontend mTLS (Client to GCP Edge)
# Run from a workstation with gcloud authenticated.
#
# Required environment variables:
#   PROJECT_ID    — GCP project ID
#   PROXY_NAME    — Name of your existing global HTTPS target proxy
#   CERT_DIR      — Directory containing cluster-ca.pem (default: ~/cluster_mtls)

set -euo pipefail

: "${PROJECT_ID:?Environment variable PROJECT_ID must be set}"
: "${PROXY_NAME:?Environment variable PROXY_NAME must be set}"

CERT_DIR="${CERT_DIR:-${HOME}/cluster_mtls}"
TRUST_CONFIG_NAME="cluster-frontend-trust"
POLICY_NAME="chef-mtls-policy"
POLICY_YAML="$(dirname "$0")/server_tls_policy.yaml"

# ── Step 1: Create GCP Trust Config ───────────────────────────────────────────
echo "==> Creating Certificate Manager Trust Config: ${TRUST_CONFIG_NAME}"
gcloud certificate-manager trust-configs create "${TRUST_CONFIG_NAME}" \
    --location=global \
    --trust-store-ca-certificates-path="${CERT_DIR}/cluster-ca.pem"

# ── Step 2: Import ServerTlsPolicy ────────────────────────────────────────────
echo "==> Importing ServerTlsPolicy: ${POLICY_NAME}"
# Substitute PROJECT_ID into the policy template before importing
PROJECT_ID="${PROJECT_ID}" envsubst < "${POLICY_YAML}" | \
  gcloud network-security server-tls-policies import "${POLICY_NAME}" \
      --source=- \
      --location=global

# ── Step 3: Attach policy to the target HTTPS proxy ───────────────────────────
echo "==> Attaching ServerTlsPolicy to HTTPS proxy: ${PROXY_NAME}"
gcloud compute target-https-proxies update "${PROXY_NAME}" \
    --server-tls-policy="projects/${PROJECT_ID}/locations/global/serverTlsPolicies/${POLICY_NAME}"

echo ""
echo "Phase 2 complete."
echo "  Trust Config : projects/${PROJECT_ID}/locations/global/trustConfigs/${TRUST_CONFIG_NAME}"
echo "  TLS Policy   : projects/${PROJECT_ID}/locations/global/serverTlsPolicies/${POLICY_NAME}"
echo "  Proxy updated: ${PROXY_NAME}"
