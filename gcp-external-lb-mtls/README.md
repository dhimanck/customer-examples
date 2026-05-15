# GCP External Load Balancer & Two-Hop mTLS for Chef Automate HA

This example walks through configuring a **Two-Hop mTLS** architecture that secures every network boundary between a chef-client and a Chef Automate HA cluster fronted by a GCP External Application Load Balancer (ALB).

## Architecture Overview

```
chef-client  ──(Hop 1 mTLS)──▶  GCP ALB  ──(Hop 2 mTLS)──▶  Habitat Nginx (backend nodes)
```

| Hop | Boundary | Authentication |
|-----|----------|----------------|
| 1 | Client → GCP ALB | Node-specific client cert issued by the cluster Root CA |
| 2 | GCP ALB → Internal Nginx | Cluster service certificate presented by the ALB |

## Directory Layout

```
gcp-external-lb-mtls/
├── README.md                   # This file
├── phase0/
│   └── export_state.sh         # Capture pre-change cluster state
├── phase1/
│   └── extract_certs.sh        # Extract PKI material from Habitat data dirs
├── phase2/
│   ├── server_tls_policy.yaml  # ServerTlsPolicy template for GCP
│   └── setup_frontend_mtls.sh  # Create Trust Config & attach to HTTPS proxy
├── phase3/
│   └── setup_backend_mtls.sh   # Upload service identity & configure backend auth
├── phase4/
│   └── mtls_patch.toml         # Habitat Nginx patch (load_balancer + cs_nginx)
├── phase5/
│   └── client.rb               # chef-client configuration for Hop 1 mTLS
└── phase6/
    ├── verify.sh               # Smoke tests (authorised and unauthorised access)
    └── rollback.sh             # Revert to previous configuration
```

## Prerequisites

- `gcloud` CLI authenticated with sufficient IAM permissions
  (`roles/certificatemanager.editor`, `roles/networksecurity.admin`,
  `roles/compute.networkAdmin`)
- `openssl` available on the Bastion / Deployment node
- `chef-automate` CLI available on the Bastion node
- Environment variable `PROJECT_ID` set to your GCP project ID
- Environment variable `FQDN` set to the DNS name of your GCP ALB
  (must match `fqdn` in `chef-automate config show`)

## Quick-Start Execution Order

```bash
# 0 — Preserve state
bash phase0/export_state.sh

# 1 — Extract cluster PKI material
bash phase1/extract_certs.sh

# 2 — Configure Hop 1 (Client → GCP ALB)
bash phase2/setup_frontend_mtls.sh

# 3 — Configure Hop 2 (GCP ALB → Internal Nginx)
bash phase3/setup_backend_mtls.sh

# 4 — Patch Habitat Nginx services
chef-automate config patch phase4/mtls_patch.toml

# 5 — Distribute client.rb to managed nodes (out-of-band per your workflow)

# 6 — Verify and, if needed, roll back
bash phase6/verify.sh
# bash phase6/rollback.sh   # only if verification fails
```

## Rollback

If any phase fails or service is interrupted:

1. Revert DNS to the internal Load Balancer VIPs.
2. Run `bash phase6/rollback.sh` to disable header enforcement in Nginx.
3. Remove the GCP ALB ServerTlsPolicy attachment to restore plain HTTPS.
