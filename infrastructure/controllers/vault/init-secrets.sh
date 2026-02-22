#
# Vault Secret Initialization Script
# Run this ONCE after Vault is deployed and running
#
# Usage:
#   ./init-secrets.sh
#
# Prerequisites:
#   - kubectl access to the cluster
#   - vault CLI installed (or use: kubectl exec -n vault vault-0 -- vault ...)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Vault Secret Initialization ===${NC}"
echo ""

# Check if running with vault CLI or kubectl exec
if command -v vault &> /dev/null; then
    echo -e "${YELLOW}Starting port-forward to Vault...${NC}"
    kubectl port-forward -n vault svc/vault 8200:8200 &
    PF_PID=$!
    sleep 3

    export VAULT_ADDR="http://127.0.0.1:8200"
    # Token should be set via environment variable or vault login
    if [ -z "$VAULT_TOKEN" ]; then
        echo -e "${RED}VAULT_TOKEN not set. Please export it first.${NC}"
        exit 1
    fi

    VAULT_CMD="vault"
    cleanup() {
        echo -e "\n${YELLOW}Cleaning up port-forward...${NC}"
        kill $PF_PID 2>/dev/null || true
    }
    trap cleanup EXIT
else
    echo -e "${YELLOW}vault CLI not found, using kubectl exec...${NC}"
    if [ -z "$VAULT_TOKEN" ]; then
        echo -e "${RED}VAULT_TOKEN not set. Please export it first.${NC}"
        exit 1
    fi
    VAULT_CMD="kubectl exec -n vault vault-0 -- env VAULT_TOKEN=${VAULT_TOKEN} vault"
fi

# Helper function to check if secret exists
secret_exists() {
    $VAULT_CMD kv get "secret/$1" >/dev/null 2>&1
}

# Helper function to create secret only if it doesn't exist
create_secret_if_missing() {
    local name=$1
    shift
    if secret_exists "$name"; then
        echo -e "${GREEN}  Secret '$name' already exists, skipping${NC}"
        return 0
    fi
    $VAULT_CMD kv put "secret/$name" "$@"
    echo -e "${GREEN}  Created secret '$name'${NC}"
}

echo ""
echo -e "${GREEN}Enabling KV v2 secrets engine...${NC}"
$VAULT_CMD secrets enable -path=secret kv-v2 2>/dev/null || echo "Secret engine already enabled"

echo ""
echo -e "${GREEN}Creating secrets (skipping existing ones)...${NC}"
echo ""

#############################################
# EDIT THESE VALUES WITH YOUR ACTUAL SECRETS
#############################################

# MikroTik (mktxp)
# ExternalSecret expects: router_host, switch_host, username, password
echo -e "${YELLOW}[1/15] Checking mktxp secrets...${NC}"
create_secret_if_missing mktxp \
    router_host="192.168.88.1" \
    switch_host="192.168.88.2" \
    ap_host="192.168.88.3" \
    username="mktxp" \
    password="$(openssl rand -hex 32)"

# Samba
echo -e "${YELLOW}[2/15] Checking samba secrets...${NC}"
create_secret_if_missing samba \
    smb_user="music" \
    smb_password="$(openssl rand -hex 64)"

# Vaultwarden
echo -e "${YELLOW}[3/15] Checking vaultwarden secrets...${NC}"
create_secret_if_missing vaultwarden \
    admin_token="$(openssl rand -hex 64)"

# Paperless-ngx
echo -e "${YELLOW}[4/15] Checking paperless secrets...${NC}"
if ! secret_exists paperless; then
    PAPERLESS_SECRET_KEY=$(openssl rand -hex 32)
    create_secret_if_missing paperless \
        admin_user="admin" \
        admin_password="$(openssl rand -hex 64)" \
        secret_key="$PAPERLESS_SECRET_KEY"
else
    echo -e "${GREEN}  Secret 'paperless' already exists, skipping${NC}"
fi

# Nextcloud
echo -e "${YELLOW}[5/15] Checking nextcloud secrets...${NC}"
create_secret_if_missing nextcloud \
    admin_user="admin" \
    admin_password="$(openssl rand -hex 64)"

# Immich
echo -e "${YELLOW}[6/15] Checking immich secrets...${NC}"
if ! secret_exists immich; then
    IMMICH_DB_PASSWORD=$(openssl rand -hex 16)
    create_secret_if_missing immich \
        db_username="immich" \
        db_password="$IMMICH_DB_PASSWORD"
else
    echo -e "${GREEN}  Secret 'immich' already exists, skipping${NC}"
fi

# Grafana
echo -e "${YELLOW}[7/15] Checking grafana secrets...${NC}"
create_secret_if_missing grafana \
    admin_user="admin" \
    admin_password="$(openssl rand -hex 64)"

# Harbor
# NOTE: secret_key MUST be exactly 16 characters (Harbor requirement)
echo -e "${YELLOW}[8/15] Checking harbor secrets...${NC}"
if ! secret_exists harbor; then
    HARBOR_SECRET_KEY=$(openssl rand -hex 8)  # 8 hex bytes = 16 chars
    create_secret_if_missing harbor \
        admin_password="$(openssl rand -hex 32)" \
        secret_key="$HARBOR_SECRET_KEY"
else
    echo -e "${GREEN}  Secret 'harbor' already exists, skipping${NC}"
fi

# Mealie
echo -e "${YELLOW}[9/15] Checking mealie secrets...${NC}"
create_secret_if_missing mealie \
    admin_email="admin@example.com" \
    admin_password="$(openssl rand -hex 32)"

# Democratic-CSI SSH key
echo -e "${YELLOW}[10/15] Checking democratic-csi SSH key...${NC}"
SSH_KEY_FILE="/tmp/democratic-csi"
if ! secret_exists democratic-csi; then
    if [ -f "$SSH_KEY_FILE" ]; then
        $VAULT_CMD kv put secret/democratic-csi \
            ssh_private_key="$(cat $SSH_KEY_FILE)"
        echo -e "${GREEN}  SSH key imported from $SSH_KEY_FILE${NC}"
    else
        echo -e "${RED}  SSH key not found at $SSH_KEY_FILE${NC}"
        echo -e "${YELLOW}  Generate it with: ssh-keygen -t ed25519 -f $SSH_KEY_FILE -N '' -C 'democratic-csi'${NC}"
        echo -e "${YELLOW}  Then add the public key to NixOS and run this script again.${NC}"
    fi
else
    echo -e "${GREEN}  Secret 'democratic-csi' already exists, skipping${NC}"
fi

# Home Assistant
echo -e "${YELLOW}[11/15] Checking homeassistant secrets...${NC}"
create_secret_if_missing homeassistant \
    placeholder="no-secrets-needed"

# GitLab
echo -e "${YELLOW}[12/15] Checking gitlab secrets...${NC}"
if ! secret_exists gitlab; then
    # Generate all required secrets
    GITLAB_DB_PASSWORD=$(openssl rand -hex 16)
    GITLAB_SECRET_KEY_BASE=$(openssl rand -hex 64)
    GITLAB_OTP_KEY_BASE=$(openssl rand -hex 64)
    GITLAB_DB_KEY_BASE=$(openssl rand -hex 64)
    GITLAB_ENCRYPTED_SETTINGS_KEY_BASE=$(openssl rand -hex 64)
    GITLAB_OPENID_CONNECT_SIGNING_KEY=$(openssl genrsa 2048 2>/dev/null)
    GITLAB_CI_JWT_SIGNING_KEY=$(openssl genrsa 2048 2>/dev/null)
    GITLAB_ROOT_PASSWORD=$(openssl rand -hex 16)
    GITLAB_RUNNER_REGISTRATION_TOKEN=$(openssl rand -hex 32)
    GITLAB_RUNNER_TOKEN=$(openssl rand -hex 32)
    GITLAB_REDIS_PASSWORD=$(openssl rand -hex 16)

    $VAULT_CMD kv put secret/gitlab \
        db_username="gitlab" \
        db_password="$GITLAB_DB_PASSWORD" \
        secret_key_base="$GITLAB_SECRET_KEY_BASE" \
        otp_key_base="$GITLAB_OTP_KEY_BASE" \
        db_key_base="$GITLAB_DB_KEY_BASE" \
        encrypted_settings_key_base="$GITLAB_ENCRYPTED_SETTINGS_KEY_BASE" \
        openid_connect_signing_key="$GITLAB_OPENID_CONNECT_SIGNING_KEY" \
        ci_jwt_signing_key="$GITLAB_CI_JWT_SIGNING_KEY" \
        root_password="$GITLAB_ROOT_PASSWORD" \
        runner_registration_token="$GITLAB_RUNNER_REGISTRATION_TOKEN" \
        runner_token="$GITLAB_RUNNER_TOKEN" \
        redis_password="$GITLAB_REDIS_PASSWORD"

    echo -e "${GREEN}  Created secret 'gitlab'${NC}"
    echo -e "${YELLOW}  GitLab root password: $GITLAB_ROOT_PASSWORD${NC}"
    echo -e "${YELLOW}  (Save this! Login as 'root' with this password)${NC}"
else
    echo -e "${GREEN}  Secret 'gitlab' already exists, skipping${NC}"
fi

# Cloudflare API Token (for cert-manager DNS challenges)
echo -e "${YELLOW}[13/15] Checking cloudflare secrets...${NC}"
create_secret_if_missing cloudflare \
    api-token="CHANGE_ME_CLOUDFLARE_API_TOKEN"

# Vikunja
echo -e "${YELLOW}[14/15] Checking vikunja secrets...${NC}"
if ! secret_exists vikunja; then
    VIKUNJA_DB_PASSWORD=$(openssl rand -hex 16)
    VIKUNJA_JWT_SECRET=$(openssl rand -hex 32)
    VIKUNJA_TYPESENSE_API_KEY=$(openssl rand -hex 32)
    $VAULT_CMD kv put secret/vikunja \
        db_username="vikunja" \
        db_password="$VIKUNJA_DB_PASSWORD" \
        jwt_secret="$VIKUNJA_JWT_SECRET" \
        typesense_api_key="$VIKUNJA_TYPESENSE_API_KEY"
    echo -e "${GREEN}  Created secret 'vikunja'${NC}"
else
    echo -e "${GREEN}  Secret 'vikunja' already exists, skipping${NC}"
fi

# AdGuard Home
echo -e "${YELLOW}[15/18] Checking adguard secrets...${NC}"
if ! secret_exists adguard; then
    ADGUARD_PASSWORD=$(openssl rand -hex 16)
    ADGUARD_BCRYPT=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'${ADGUARD_PASSWORD}', bcrypt.gensalt()).decode())" 2>/dev/null || echo "GENERATE_BCRYPT_MANUALLY")
    create_secret_if_missing adguard \
        username="admin" \
        password="$ADGUARD_PASSWORD" \
        password_bcrypt="$ADGUARD_BCRYPT"
    echo -e "${YELLOW}  AdGuard password: $ADGUARD_PASSWORD${NC}"
    echo -e "${YELLOW}  (Save this! You'll need it to log in)${NC}"
else
    echo -e "${GREEN}  Secret 'adguard' already exists, skipping${NC}"
fi

# Funkwhale
echo -e "${YELLOW}[16/18] Checking funkwhale secrets...${NC}"
create_secret_if_missing funkwhale \
    django_secret_key="$(openssl rand -base64 45)"

# mktxp AP host
echo -e "${YELLOW}[17/18] Checking mktxp ap_host...${NC}"
echo -e "${YELLOW}  Note: If mktxp needs ap_host, update it manually:${NC}"
echo -e "${YELLOW}  vault kv patch secret/mktxp ap_host=192.168.88.3${NC}"

# Authentik
echo -e "${YELLOW}[18/18] Checking authentik secrets...${NC}"
if ! secret_exists authentik; then
    $VAULT_CMD kv put secret/authentik \
        db_username="authentik" \
        db_password="$(openssl rand -hex 32)" \
        secret_key="$(openssl rand -hex 32)" \
        admin_password="$(openssl rand -hex 16)" \
        admin_token="$(openssl rand -hex 32)" \
        grafana_client_secret="$(openssl rand -hex 32)" \
        immich_client_secret="$(openssl rand -hex 32)" \
        gitlab_client_secret="$(openssl rand -hex 32)" \
        mealie_client_secret="$(openssl rand -hex 32)" \
        vikunja_client_secret="$(openssl rand -hex 32)" \
        paperless_client_secret="$(openssl rand -hex 32)" \
        harbor_client_secret="$(openssl rand -hex 32)"
    echo -e "${GREEN}  Created secret 'authentik'${NC}"
else
    echo -e "${GREEN}  Secret 'authentik' already exists, skipping${NC}"
fi

echo ""
echo -e "${GREEN}=== Secrets initialized! ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Edit this script and replace all $(openssl rand -hex 64)"
echo ""
echo "To update a secret later:"
echo "  vault kv put secret/<app> key=value"
echo ""
echo "To read a secret:"
echo "  vault kv get secret/<app>"
echo ""
echo -e "${GREEN}Triggering ExternalSecret refresh...${NC}"
kubectl annotate externalsecrets -A force-sync=$(date +%s) --all --overwrite 2>/dev/null || true

echo ""
echo -e "${GREEN}Done! Check ExternalSecret status with:${NC}"
echo "  kubectl get externalsecrets -A"
