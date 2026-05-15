# Phase 5 — Chef Infra Client Configuration
#
# Add these settings to /etc/chef/client.rb on every managed node so that
# chef-client presents its identity certificate to the GCP Load Balancer
# (Hop 1 mTLS) and trusts the cluster Root CA when verifying the server.
#
# Distribute certificates to each node before modifying client.rb:
#   /etc/chef/ssl/client.crt          — Node-specific client certificate
#   /etc/chef/ssl/client.key          — Node-specific private key
#   /etc/chef/trusted_certs/cluster-ca.crt — Cluster Root CA (from Phase 1)

# Replace YOUR_FQDN and YOUR_ORG with your actual ALB hostname and Chef organisation name.
chef_server_url         "https://YOUR_FQDN/organizations/YOUR_ORG"

# ── Hop 1: Client → GCP ALB mTLS settings ─────────────────────────────────────
# Verify the server certificate presented by the GCP ALB.
ssl_verify_mode         :verify_peer

# Directory where the cluster Root CA (and any other trusted CAs) are stored.
trusted_certs_dir       "/etc/chef/trusted_certs"

# Present the node-specific client certificate during the TLS handshake so that
# the GCP ALB can verify this node against the cluster Trust Config.
ssl_client_cert         "/etc/chef/ssl/client.crt"
ssl_client_key          "/etc/chef/ssl/client.key"
