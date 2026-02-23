#!/usr/bin/env bash
#
# Homelab Bootstrap Script
# Run this ONCE after NixOS is deployed on zion
#
# Prerequisites:
#   - NixOS deployed on zion and nixos nodes
#   - ZFS pool 'tank' exists
#   - SSH access to zion
#   - GitHub SSH key configured for FluxCD
#
# Usage:
#   ./bootstrap.sh [--skip-zfs] [--skip-flux] [--cloudflare-token TOKEN]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Parse arguments
SKIP_ZFS=false
SKIP_FLUX=false
CLOUDFLARE_TOKEN=""
GITHUB_REPO="liberis/homelab"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-zfs) SKIP_ZFS=true; shift ;;
        --skip-flux) SKIP_FLUX=true; shift ;;
        --cloudflare-token) CLOUDFLARE_TOKEN="$2"; shift 2 ;;
        --github-repo) GITHUB_REPO="$2"; shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Verify we're on the right node
if [[ "$(hostname)" != "mainframe" ]]; then
    warn "This script is designed to run on mainframe (server node)"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

#############################################
# PHASE 1: ZFS Datasets
#############################################
step "Phase 1: ZFS Datasets"

if [[ "$SKIP_ZFS" == "true" ]]; then
    log "Skipping ZFS setup (--skip-zfs)"
else
    # Check if datasets already exist
    if zfs list tank/k8s/volumes &>/dev/null; then
        log "ZFS datasets already exist, skipping"
    else
        log "Creating ZFS datasets for k3s..."

        # k3s volumes (democratic-csi)
        zfs create -o recordsize=128K -o compression=lz4 -o atime=off \
            -o xattr=sa -o mountpoint=none tank/k8s
        zfs create -o mountpoint=none tank/k8s/volumes
        zfs create -o mountpoint=none tank/k8s/snapshots

        # Set NFS sharing
        zfs set sharenfs="rw,no_subtree_check,no_root_squash" tank/k8s/volumes
        zfs set sharenfs="rw,no_subtree_check,no_root_squash" tank/k8s/snapshots

        log "ZFS datasets created"
    fi
fi

#############################################
# PHASE 2: FluxCD Bootstrap
#############################################
step "Phase 2: FluxCD Bootstrap"

if [[ "$SKIP_FLUX" == "true" ]]; then
    log "Skipping FluxCD bootstrap (--skip-flux)"
elif kubectl get namespace flux-system &>/dev/null; then
    log "FluxCD already installed, skipping bootstrap"
else
    log "Bootstrapping FluxCD..."

    # Check for GitHub SSH key
    if [[ ! -f ~/.ssh/id_ed25519 ]] && [[ ! -f ~/.ssh/id_rsa ]]; then
        warn "No SSH key found for GitHub"
        warn "Generate one with: ssh-keygen -t ed25519"
        warn "Add it to GitHub: https://github.com/settings/keys"
        read -p "Press Enter after configuring GitHub SSH..."
    fi

    flux bootstrap github \
        --owner="${GITHUB_REPO%/*}" \
        --repository="${GITHUB_REPO#*/}" \
        --path=clusters/zion \
        --personal

    log "FluxCD bootstrapped"
fi

#############################################
# PHASE 3: Wait for Vault Pod
#############################################
step "Phase 3: Wait for Vault"

log "Waiting for Vault namespace..."
until kubectl get namespace vault &>/dev/null; do
    sleep 5
done

log "Waiting for Vault pod to be created..."
until kubectl get pod vault-0 -n vault &>/dev/null; do
    sleep 5
done

log "Waiting for Vault pod to be running..."
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=300s 2>/dev/null || true

# Check if Vault is initialized
sleep 5
VAULT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null || echo '{}')
INITIALIZED=$(echo "$VAULT_STATUS" | grep -o '"initialized": *[^,]*' | awk '{print $2}' || echo "false")

#############################################
# PHASE 4: Initialize Vault (if needed)
#############################################
step "Phase 4: Vault Initialization"

if [[ "$INITIALIZED" == "true" ]]; then
    log "Vault already initialized"
else
    log "Initializing Vault..."

    INIT_OUTPUT=$(kubectl exec -n vault vault-0 -- vault operator init -format=json)

    # Extract keys
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep -o '"root_token": *"[^"]*"' | cut -d'"' -f4)
    UNSEAL_KEY=$(echo "$INIT_OUTPUT" | grep -o '"unseal_keys_b64":\s*\[[^]]*\]' | grep -o '"[^"]*"' | head -1 | tr -d '"')

    # Save to file (IMPORTANT: secure this!)
    VAULT_KEYS_FILE="/root/.vault-keys"
    cat > "$VAULT_KEYS_FILE" << EOF
# Vault Keys - KEEP THIS SECURE!
# Generated: $(date)
ROOT_TOKEN=$ROOT_TOKEN
UNSEAL_KEY=$UNSEAL_KEY

# Full init output:
$INIT_OUTPUT
EOF
    chmod 600 "$VAULT_KEYS_FILE"

    warn "Vault keys saved to $VAULT_KEYS_FILE"
    warn "BACK THIS UP SECURELY AND DELETE FROM SERVER!"

    # Create Kubernetes secrets
    log "Creating Kubernetes secrets for Vault..."
    kubectl create secret generic vault-unseal-key -n vault \
        --from-literal=unseal-key="$UNSEAL_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic vault-root-token -n vault \
        --from-literal=token="$ROOT_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

    log "Vault initialized and secrets created"

    # Export for later use
    export VAULT_TOKEN="$ROOT_TOKEN"
fi

#############################################
# PHASE 5: Wait for Vault Unseal & Auth
#############################################
step "Phase 5: Wait for Vault Configuration"

log "Waiting for Vault to be unsealed..."
for i in {1..30}; do
    SEALED=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | \
        grep -o '"sealed": *[^,]*' | awk '{print $2}' || echo "true")
    if [[ "$SEALED" == "false" ]]; then
        log "Vault is unsealed"
        break
    fi
    log "Vault still sealed, waiting... ($i/30)"
    sleep 10
done

log "Waiting for Kubernetes auth to be configured..."
for i in {1..12}; do
    if kubectl exec -n vault vault-0 -- sh -c "vault read auth/kubernetes/role/external-secrets" &>/dev/null; then
        log "Kubernetes auth is configured"
        break
    fi
    log "Waiting for kubernetes-auth CronJob... ($i/12)"
    sleep 30
done

#############################################
# PHASE 6: Populate Secrets
#############################################
step "Phase 6: Populate Vault Secrets"

# Get root token if not set
if [[ -z "$VAULT_TOKEN" ]]; then
    VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
fi
export VAULT_TOKEN

# Check if Cloudflare token was provided
if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
    warn "Cloudflare API token not provided"
    warn "Certificates will fail until you set it manually:"
    warn "  vault kv put secret/cloudflare api-token=YOUR_TOKEN"
    echo ""
    read -p "Enter Cloudflare API token (or press Enter to skip): " CLOUDFLARE_TOKEN
fi

# Run the init-secrets script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../infrastructure/controllers/vault/init-secrets.sh" ]]; then
    log "Running init-secrets.sh..."

    # Set Cloudflare token if provided
    if [[ -n "$CLOUDFLARE_TOKEN" ]]; then
        kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
            vault kv put secret/cloudflare api-token="$CLOUDFLARE_TOKEN"
        log "Cloudflare token set"
    fi

    # Run the init script
    bash "$SCRIPT_DIR/../infrastructure/controllers/vault/init-secrets.sh"
else
    warn "init-secrets.sh not found, skipping"
fi

#############################################
# PHASE 7: Trigger Reconciliation
#############################################
step "Phase 7: Trigger FluxCD Reconciliation"

log "Triggering full reconciliation..."
flux reconcile kustomization flux-system --with-source
sleep 5
flux reconcile kustomization infrastructure-controllers
sleep 5
flux reconcile kustomization infrastructure-configs
sleep 5
flux reconcile kustomization apps --with-source

#############################################
# PHASE 8: Status Check
#############################################
step "Phase 8: Deployment Status"

log "Checking HelmRelease status..."
kubectl get helmreleases -A

echo ""
log "Checking for failing pods..."
kubectl get pods -A | grep -v Running | grep -v Completed | head -20

echo ""
log "Checking ExternalSecrets..."
kubectl get externalsecrets -A | head -20

#############################################
# Summary
#############################################
step "Bootstrap Complete!"

cat << 'EOF'
Next steps:

1. Monitor deployment progress:
   watch kubectl get helmreleases -A

2. Check for issues:
   kubectl get pods -A | grep -v Running | grep -v Completed

3. Access services:
   - Vault UI: https://vault.liberispat.com
   - Authentik: https://auth.liberispat.com
   - Grafana: https://grafana.liberispat.com

4. IMPORTANT: Secure your Vault keys!
   - Back up /root/.vault-keys to a secure location
   - Delete it from the server after backup

5. If certificates fail:
   - Verify Cloudflare token: vault kv get secret/cloudflare
   - Check cert-manager logs: kubectl logs -n cert-manager -l app=cert-manager

6. If storage fails:
   - Verify controller is on akasha: kubectl get pods -n democratic-csi -o wide
   - Check democratic-csi logs: kubectl logs -n democratic-csi -l app.kubernetes.io/csi-role=controller -c csi-driver

EOF
