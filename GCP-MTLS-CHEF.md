# GCP External Load Balancer & Two-Hop mTLS for Chef Automate HA

## 1. Architectural Strategy
This implementation utilizes a **Two-Hop mTLS** model to secure every network boundary:
* **Hop 1 (Client to Edge):** The `chef-client` authenticates to the **GCP External Application Load Balancer (ALB)**. Handshake validation is anchored to the existing cluster Root CA.
* **Hop 2 (Edge to Internal):** The **GCP ALB** authenticates to the **Internal Tier** (Primary/Secondary LBs and backend Nginx). The ALB presents an existing cluster-issued certificate to ensure internal traffic remains mutually authenticated.

## 2. Phase 0: System State Preservation (**Execute on Bastion Host**)
Capture the current validated state of your Habitat-managed services before making infrastructure changes.

1. **Export Current Cluster State:**
   ```bash
   chef-automate config show > automate_ha_pre_mtls_backup.toml
   ```

2. **Verify FQDN:** Ensure the `fqdn` defined in your configuration matches the DNS record intended for your GCP ALB.

## 3. Phase 1: Repurpose Existing Certificates (Execute on Bastion Host)
Extract the existing PKI infrastructure directly from the Habitat service data directories.

1. **Extract the Root CA Bundle:**
   The Root CA that anchors the entire HA deployment is found in the deployment service data directory.
   ```bash
   mkdir -p ~/cluster_mtls
   sudo cp /hab/svc/automate-ha-deployment/data/root-ca.crt ~/cluster_mtls/cluster-ca.pem
   ```

2. **Extract Service Identity Certificates:**
   Identify the server certificate and key currently used by the load balancer service.
   ```bash
   # These paths are dynamically generated based on your cluster FQDN
   # Verification path: /hab/svc/automate-load-balancer/config/nginx.conf
   sudo cp /hab/svc/automate-load-balancer/data/$(hostname -f).cert ~/cluster_mtls/service.crt
   sudo cp /hab/svc/automate-load-balancer/data/$(hostname -f).key ~/cluster_mtls/service.key
   ```

3. **Verify clientAuth EKU:**
   GCP requires that client certificates explicitly include the `clientAuth` Extended Key Usage.
   ```bash
   openssl x509 -in ~/cluster_mtls/cluster-ca.pem -text -noout | grep -A2 "Extended Key Usage"
   ```

## 4. Phase 2: Hop 1 — Frontend mTLS (Execute on Bastion Host / GCP CLI)
Configure the GCP edge to enforce certificate requirements using your repurposed Root CA.

1. **Create GCP Trust Config:**
   ```bash
   gcloud certificate-manager trust-configs create cluster-frontend-trust \
       --location=global \
       --trust-store-ca-certificates-path=~/cluster_mtls/cluster-ca.pem
   ```

2. **Establish ServerTlsPolicy (Strict Enforcement):**
   ```bash
   cat << EOF > server_tls_policy.yaml
   mtlsPolicy:
     clientValidationMode: REJECT_INVALID
     clientValidationTrustConfig: projects/${PROJECT_ID}/locations/global/trustConfigs/cluster-frontend-trust
   EOF

   gcloud network-security server-tls-policies import chef-mtls-policy \
       --source=server_tls_policy.yaml --location=global
   ```

3. **Attach to Target HTTPS Proxy:**
   Update your global HTTPS proxy to reference this policy.

## 5. Phase 3: Hop 2 — Backend mTLS (Execute on Bastion Host / GCP CLI)
The GCP ALB authenticates to your internal tier using the existing service identity.

1. **Upload Existing Service Identity to GCP:**
   ```bash
   gcloud certificate-manager certificates create gcp-lb-identity \
       --certificate-file=~/cluster_mtls/service.crt \
       --private-key-file=~/cluster_mtls/service.key \
       --scope=client-auth --location=global
   ```

2. **Configure Backend Authentication:**
   ```bash
   gcloud network-security backend-authentication-configs create cluster-backend-auth \
       --trust-config=cluster-frontend-trust \
       --client-certificate=gcp-lb-identity --location=global
   ```

3. **Enable Custom Request Headers:**
   Configure the backend service to forward validation state to the application nodes.
   ```bash
   gcloud compute backend-services update [BACKEND_SERVICE_NAME] \
       --custom-request-header='X-Client-Cert-Verified:{client_cert_chain_verified}' \
       --global
   ```

## 6. Phase 4: Internal Tier & Cluster Patching

### A. Internal Load Balancers (Execute on Primary/Secondary LB VMs)
Switch the internal Primary and Secondary LBs to TCP Mode for the Chef Infra Server API. This allows the mTLS handshake from the GCP ALB to reach the Habitat-managed Nginx on the nodes without interference.

### B. Habitat Nginx Patch (Execute on Bastion Host)
Apply this patch to trust GCP IP ranges and enforce the mTLS header validation. Use the `extra_config` block as an "escape hatch" for Nginx directives not natively in the TOML schema.

```toml
[load_balancer.v1.sys.ngx.http]
  include_x_forwarded_for = true
  extra_config = """
set_real_ip_from 130.211.0.0/22;
set_real_ip_from 35.191.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;

# Enforce mTLS based on verification headers from GCP ALB
if ($http_x_client_cert_verified != "true") {
    return 403 "mTLS certificate verification required at edge";
}
"""

[cs_nginx.v1.sys.ngx.http]
  extra_config = """
set_real_ip_from 130.211.0.0/22;
set_real_ip_from 35.191.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
"""
```

**Apply Patch:** `chef-automate config patch mtls_config.toml`

## 7. Phase 5: Chef Infra Client Configuration (Execute on Managed Nodes)
Update the `client.rb` on managed nodes to present the node's identity to the GCP ALB.

1. **Distribute Certificates:** Ensure certificates are placed in standard directories.

2. **Update `client.rb`:**
   ```ruby
   chef_server_url         "https://chef-automate.example.com/organizations/your-org"

   # mTLS settings for Hop 1
   ssl_verify_mode         :verify_peer
   trusted_certs_dir       "/etc/chef/trusted_certs"
   ssl_client_cert         "/etc/chef/ssl/client.crt"
   ssl_client_key          "/etc/chef/ssl/client.key"
   ```

## 8. Phase 6: Verification & Troubleshooting

### Troubleshooting: If Patch is Rejected
If the `chef-automate config patch` command fails:

* **Syntax:** Verify the `extra_config` block uses triple quotes (`"""`) for multi-line strings.
* **Schema:** If the CLI rejects the key, ensure it is within the correct service block (`[load_balancer.v1.sys.ngx.http]`).

### Verification
* **Authorized:** Execute `chef-client`. Success is indicated by HTTP 200.
* **Unauthorized:** Attempt `curl -I https://[FQDN]` without a certificate. Expected result is `403 Forbidden` generated by the GCP ALB.
* **Audit:** Check `/hab/svc/automate-load-balancer/var/log/nginx/access.log` to confirm the actual client IP is parsed from the `X-Forwarded-For` header.

## 9. Rollback (if needed to be executed on Bastion Host)
To revert header enforcement without a destructive configuration reset:

```bash
chef-automate config patch <(echo '[load_balancer.v1.sys.ngx.http]
include_x_forwarded_for = false')
```

