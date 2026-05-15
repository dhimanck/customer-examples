#!/usr/bin/env bash
# Phase 0 — System State Preservation
# Run on the Bastion / Deployment node BEFORE making any infrastructure changes.
# Captures the current validated state of Habitat-managed services so that a
# clean rollback baseline exists.

set -euo pipefail

OUTPUT_FILE="${OUTPUT_FILE:-automate_ha_pre_mtls.toml}"

echo "==> Exporting current Chef Automate cluster configuration to: ${OUTPUT_FILE}"
chef-automate config show > "${OUTPUT_FILE}"

echo "==> Verifying FQDN in exported configuration:"
grep -E '^\s*fqdn\s*=' "${OUTPUT_FILE}" || \
    echo "    WARNING: 'fqdn' key not found. Confirm the fqdn matches the DNS record for your GCP ALB." >&2

echo ""
echo "==> Reminder: Back up the configuration of your Primary and Secondary"
echo "    internal Load Balancers. They will be reconfigured in Phase 4 to"
echo "    operate in TCP mode for the Chef Infra Server API paths."
echo ""
echo "Phase 0 complete. Baseline saved to: ${OUTPUT_FILE}"
