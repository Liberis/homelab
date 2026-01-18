# Homelab Kubernetes Infrastructure

GitOps-managed Kubernetes homelab running on k3s with FluxCD for continuous delivery.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL ACCESS                                 │
│                         (Cloudflare DNS + Let's Encrypt)                    │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INGRESS LAYER                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────────┐  │
│  │   Traefik   │    │   MetalLB   │    │        cert-manager             │  │
│  │  (Ingress)  │◄───│    (L2)     │    │  (Wildcard TLS via Cloudflare)  │  │
│  └─────────────┘    └─────────────┘    └─────────────────────────────────┘  │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
        ▼                             ▼                             ▼
┌───────────────┐           ┌─────────────────┐           ┌─────────────────┐
│    SECRETS    │           │   MONITORING    │           │    STORAGE      │
│               │           │                 │           │                 │
│ ┌───────────┐ │           │ ┌─────────────┐ │           │ ┌─────────────┐ │
│ │   Vault   │ │           │ │ Prometheus  │ │           │ │Democratic-CSI│ │
│ └───────────┘ │           │ ├─────────────┤ │           │ │  (ZFS/NFS)  │ │
│ ┌───────────┐ │           │ │  Grafana    │ │           │ └─────────────┘ │
│ │ External  │ │           │ ├─────────────┤ │           │ ┌─────────────┐ │
│ │ Secrets   │ │           │ │    Loki     │ │           │ │ CloudNativePG│ │
│ └───────────┘ │           │ └─────────────┘ │           │ │ (PostgreSQL)│ │
└───────────────┘           └─────────────────┘           └─────────────────┘
        │                             │                             │
        └─────────────────────────────┼─────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              APPLICATIONS                                    │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │     MEDIA       │  │  PRODUCTIVITY   │  │        SELF-HOSTED          │  │
│  │                 │  │                 │  │                             │  │
│  │ • Jellyfin      │  │ • Mealie        │  │ • Vaultwarden (passwords)   │  │
│  │ • Navidrome     │  │ • Paperless-ngx │  │ • Immich (photos)           │  │
│  │ • Audiobookshelf│  │ • Vikunja       │  │ • GitLab (code)             │  │
│  │ • *arr suite    │  │ • Actual Budget │  │ • Harbor (registry)         │  │
│  │ • qBittorrent   │  │                 │  │ • Home Assistant            │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                                   │
│  │       DNS       │  │    UTILITIES    │                                   │
│  │                 │  │                 │                                   │
│  │ • AdGuard Home  │  │ • Uptime Kuma   │                                   │
│  │ • Unbound       │  │ • Headlamp      │                                   │
│  │                 │  │ • Glance        │                                   │
│  └─────────────────┘  └─────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                               GITOPS (FluxCD)                                │
│                                                                             │
│   GitHub Repo ──► Flux Source Controller ──► Flux Kustomize Controller      │
│                                          ──► Flux Helm Controller           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| Kubernetes | k3s |
| GitOps | FluxCD v2 |
| Ingress | Traefik |
| Load Balancer | MetalLB (L2) |
| TLS | cert-manager + Let's Encrypt |
| Secrets | HashiCorp Vault + External Secrets |
| Storage | Democratic-CSI (ZFS/NFS) |
| Database | CloudNativePG (PostgreSQL) |
| Monitoring | Prometheus + Grafana + Loki |
| DNS | AdGuard Home + Unbound |

## Repository Structure

```
├── clusters/
│   └── jarvis/              # Cluster entry point
│       ├── flux-system/     # FluxCD components
│       ├── infrastructure.yaml
│       └── apps.yaml
├── infrastructure/
│   ├── controllers/         # Operators & controllers
│   │   ├── metallb/
│   │   ├── traefik/
│   │   ├── cert-manager/
│   │   ├── vault/
│   │   └── ...
│   └── configs/             # Controller configurations
│       ├── certificates/
│       ├── metallb/
│       └── ...
└── apps/                    # Application deployments
    ├── monitoring/
    ├── jellyfin/
    ├── immich/
    └── ...
```

## Deployment Order

FluxCD manages dependencies automatically:

```
1. infrastructure/controllers  (MetalLB, Traefik, Vault, etc.)
         │
         ▼
2. infrastructure/configs      (Certificates, IP pools, etc.)
         │
         ▼
3. apps/                       (All applications)
```

## Secret Management

All secrets are stored in HashiCorp Vault and synced to Kubernetes via External Secrets Operator:

```yaml
# Example: ExternalSecret pulls from Vault
apiVersion: external-secrets.io/v1
kind: ExternalSecret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  data:
    - secretKey: password
      remoteRef:
        key: secret/myapp
        property: password
```

**No secrets are stored in this repository.**

## Quick Start

1. **Prerequisites**
   - k3s cluster
   - Vault instance with secrets configured
   - ZFS storage pool with NFS exports

2. **Bootstrap FluxCD**
   ```bash
   flux bootstrap github \
     --owner=<github-user> \
     --repository=homelab \
     --path=clusters/jarvis \
     --personal
   ```

3. **Configure Vault**
   ```bash
   kubectl create secret generic vault-root-token \
     -n vault --from-literal=token=<ROOT_TOKEN>
   ```

## Network Topology

| Service | Internal | External |
|---------|----------|----------|
| Traefik | 10.43.x.x | 192.168.1.200 |
| AdGuard | 10.43.x.x | 192.168.1.201 |
| Unbound | 10.43.x.x | 192.168.1.202 |

## License

MIT
