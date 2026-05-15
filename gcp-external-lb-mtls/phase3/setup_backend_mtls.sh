#!/usr/bin/env bash
# Phase 3 — Hop 2: Backend mTLS (GCP Edge to Internal Nginx)
# Run from a workstation with gcloud authenticated.
#
# The GCP ALB will present the cluster service identity certificate to the
# Habitat-managed Nginx nodes so that the internal mTLS handshake can be
# validated by the backend.
#
# Required environment variables:
#   PROJECT_ID           — GCP project ID
#   BACKEND_SERVICE_NAME — Name of your existing global backend service
#   CERT_DIR             — Directory containing service.crt / service.key
#                          (default: ~/cluster_mtls)

set -euo pipefail

: "${PROJECT_ID:?Environment variable PROJECT_ID must be set}"
: "${BACKEND_SERVICE_NAME:?Environment variable BACKEND_SERVICE_NAME must be set}"

CERT_DIR="${CERT_DIR:-${HOME}/cluster_mtls}"
CERT_NAME="gcp-lb-identity"
BACKEND_AUTH_NAME="cluster-backend-auth"
TRUST_CONFIG_NAME="cluster-frontend-trust"

# ── Step 1: Upload Service Identity Certificate to Certificate Manager ─────────
echo "==> Uploading service identity certificate as: ${CERT_NAME}"
gcloud certificate-manager certificates create "${CERT_NAME}" \
    --certificate-file="${CERT_DIR}/service.crt" \
    --private-key-file="${CERT_DIR}/service.key" \
    --scope=client-auth \
    --location=global

# ── Step 2: Create Backend Authentication Config ───────────────────────────────
echo "==> Creating BackendAuthenticationConfig: ${BACKEND_AUTH_NAME}"
gcloud network-security backend-authentication-configs create "${BACKEND_AUTH_NAME}" \
    --trust-config="${TRUST_CONFIG_NAME}" \
    --client-certificate="${CERT_NAME}" \
    --location=global

# ── Step 3: Forward mTLS Verification Headers to Application Nodes ─────────────
# The custom request header passes the ALB's mTLS verification result to the
# Habitat Nginx services so they can enforce it at the application layer.
echo "==> Configuring custom request header on backend service: ${BACKEND_SERVICE_NAME}"
gcloud compute backend-services update "${BACKEND_SERVICE_NAME}" \
    --custom-request-header='X-Client-Cert-Verified:{client_cert_chain_verified}' \
    --global

echo ""
echo "Phase 3 complete."
echo "  Certificate  : ${CERT_NAME}"
echo "  Backend Auth : ${BACKEND_AUTH_NAME}"
echo "  Header added : X-Client-Cert-Verified on ${BACKEND_SERVICE_NAME}"
