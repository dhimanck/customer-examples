#!/usr/bin/env bash
# Phase 1 — Repurpose Existing Certificates
# Run on the Bastion / Deployment node.
# Extracts the Root CA bundle and service identity certificates from the
# Habitat service data directories so they can be uploaded to GCP in later phases.

set -euo pipefail

CERT_DIR="${CERT_DIR:-${HOME}/cluster_mtls}"

echo "==> Creating certificate staging directory: ${CERT_DIR}"
mkdir -p "${CERT_DIR}"

# ── Root CA Bundle ─────────────────────────────────────────────────────────────
ROOT_CA_SRC="/hab/svc/automate-ha-deployment/data/root-ca.crt"
ROOT_CA_DST="${CERT_DIR}/cluster-ca.pem"

echo "==> Copying Root CA from ${ROOT_CA_SRC}"
sudo cp "${ROOT_CA_SRC}" "${ROOT_CA_DST}"
sudo chown "$(id -u):$(id -g)" "${ROOT_CA_DST}"
chmod 644 "${ROOT_CA_DST}"

# ── Service Identity Certificates ─────────────────────────────────────────────
# The paths are dynamically constructed from the node's fully-qualified domain name.
FQDN="$(hostname -f)"
SERVICE_CERT_SRC="/hab/svc/automate-load-balancer/data/${FQDN}.cert"
SERVICE_KEY_SRC="/hab/svc/automate-load-balancer/data/${FQDN}.key"
SERVICE_CERT_DST="${CERT_DIR}/service.crt"
SERVICE_KEY_DST="${CERT_DIR}/service.key"

echo "==> Copying service certificate from ${SERVICE_CERT_SRC}"
sudo cp "${SERVICE_CERT_SRC}" "${SERVICE_CERT_DST}"
sudo chown "$(id -u):$(id -g)" "${SERVICE_CERT_DST}"
chmod 644 "${SERVICE_CERT_DST}"

echo "==> Copying service private key from ${SERVICE_KEY_SRC}"
sudo cp "${SERVICE_KEY_SRC}" "${SERVICE_KEY_DST}"
sudo chown "$(id -u):$(id -g)" "${SERVICE_KEY_DST}"
chmod 600 "${SERVICE_KEY_DST}"

# ── Verify clientAuth EKU ──────────────────────────────────────────────────────
# GCP requires that certificates used for client authentication explicitly include
# the clientAuth Extended Key Usage (OID 1.3.6.1.5.5.7.3.2).
echo ""
echo "==> Verifying Extended Key Usage on Root CA (clientAuth required for GCP):"
openssl x509 -in "${ROOT_CA_DST}" -text -noout | grep -A2 "Extended Key Usage" || \
  echo "    WARNING: Extended Key Usage section not found. Confirm clientAuth is present."

echo ""
echo "==> Certificate inventory in ${CERT_DIR}:"
ls -lh "${CERT_DIR}"

echo ""
echo "Phase 1 complete. Certificates staged in: ${CERT_DIR}"
