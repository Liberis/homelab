#!/bin/bash
# Vault Secret Initialization Script
# Run this ONCE after Vault is deployed and running
#
# Usage:
#   export VAULT_ADDR=https://vault.liberispat.com
#   export VAULT_TOKEN=root  # Change in production
#   ./vault-init.sh

set -e

echo "=== Initializing Vault Secrets ==="

# Enable KV v2 secrets engine (if not already enabled)
vault secrets enable -path=secret kv-v2 2>/dev/null || echo "Secret engine already enabled"

echo "Creating secrets..."

# MikroTik (mktxp)
vault kv put secret/mktxp \
    router_host="192.168.88.1" \
    router_username="mktxp" \
    router_password="mktxp82465!@#$"


# Samba
vault kv put secret/samba \
    smb_user="music" \
    smb_password="music"

# Vaultwarden
vault kv put secret/vaultwarden \
    admin_token="admintoken"

# Paperless-ngx
vault kv put secret/paperless \
    admin_user="admin" \
    admin_password="admin" \
    secret_key="$(openssl rand -hex 32)"

# Nextcloud
vault kv put secret/nextcloud \
    admin_user="admin" \
    admin_password="admin"

# Immich
vault kv put secret/immich \
    db_username="immich" \
    db_password="$(openssl rand -hex 16)"

# Grafana
vault kv put secret/grafana \
    admin_password="admin"

echo "=== Vault secrets initialized ==="
echo ""
echo "IMPORTANT: Update the placeholder passwords above with real values!"
echo "You can update individual secrets with:"
echo "  vault kv put secret/<app> key=value"
