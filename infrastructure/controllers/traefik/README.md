# Traefik Ingress Controller

Traefik handles all external traffic routing for the homelab cluster.

## Architecture

```
                     192.168.10.11 (MetalLB)
                           │
                    ┌──────┴──────┐
                    │   Traefik   │
                    │  (traefik)  │
                    └──────┬──────┘
      ┌────────┬──────────┼──────────┬─────────┐
     80/443   53/tcp    53/udp     445      2222
      │         │          │         │         │
   Ingress   AdGuard   AdGuard    Samba    GitLab
   (HTTP)    DNS-TCP   DNS-UDP     SMB       SSH
```

## Entrypoints

| Port | Protocol | Name        | Target Service      |
|------|----------|-------------|---------------------|
| 80   | TCP      | web         | HTTP → HTTPS redirect |
| 443  | TCP      | websecure   | HTTPS Ingress       |
| 53   | TCP      | dns-tcp     | AdGuard DNS         |
| 53   | UDP      | dns-udp     | AdGuard DNS         |
| 445  | TCP      | smb         | Samba               |
| 2222 | TCP      | gitlab-ssh  | GitLab SSH          |

## Routing

- **HTTP/HTTPS**: Standard Kubernetes Ingress resources
- **TCP/UDP**: Traefik IngressRouteTCP/IngressRouteUDP CRDs

## Hairpin NAT

Pods resolve `*.liberispat.com` to Traefik's ClusterIP (`10.43.0.100`) via CoreDNS custom zone file. This allows pods to access services using external URLs.

See: `infrastructure/configs/coredns/coredns-custom.yaml`

## TLS

Default wildcard certificate: `liberispat-wildcard-tls` (cert-manager managed)

See: `infrastructure/configs/certificates/liberispat-wildcard.yaml`
