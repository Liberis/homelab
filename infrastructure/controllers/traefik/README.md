# Traefik Dual-Instance Setup

## Architecture

Two Traefik instances, split by network speed and independence requirements:

| Instance | Node | IP | IngressClass | Network | Purpose |
|----------|------|----|-------------|---------|---------|
| traefik | akasha | 192.168.10.102 | `traefik` (default) | 2.5Gbps | High-bandwidth apps (immich, jellyfin, etc.) |
| traefik-mainframe | mainframe | 192.168.10.101 | `traefik-mainframe` | 1Gbps | Control plane apps (auth, DNS UI, passwords, hass) |

Apps pinned to mainframe use `ingressClassName: traefik-mainframe` in their Ingress resources. All others use `traefik` (default).

AdGuard DNS rewrites route each domain to the correct Traefik IP.

## Entrypoints

### akasha (traefik)

| Port | Protocol | Name | Target |
|------|----------|------|--------|
| 80 | TCP | web | HTTP -> HTTPS redirect |
| 443 | TCP | websecure | HTTPS Ingress |
| 445 | TCP | smb | Samba |
| 2222 | TCP | gitlab-ssh | GitLab SSH |

### mainframe (traefik-mainframe)

| Port | Protocol | Name | Target |
|------|----------|------|--------|
| 80 | TCP | web | HTTP -> HTTPS redirect |
| 443 | TCP | websecure | HTTPS Ingress |

## TLS Configuration

Both instances use a Let's Encrypt wildcard certificate (`*.liberispat.com`) issued via Cloudflare DNS01 challenge. Each namespace (`traefik`, `traefik-mainframe`) has its own Certificate resource and TLSStore `default` pointing to `liberispat-wildcard-tls`.

Ingress resources do **not** specify `tls.secretName` -- the TLSStore default cert handles all TLS termination.

## Hairpin NAT

Pods resolve `*.liberispat.com` to Traefik's ClusterIP (`10.43.0.100`) via CoreDNS custom zone file. This allows pods to access services using external URLs.

See: `infrastructure/configs/coredns/coredns-custom.yaml`

## Known Issues and Fixes

### TLSStore conflict with allowCrossNamespace

**Problem:** When both Traefik instances have `kubernetesCRD.allowCrossNamespace: true` without namespace restrictions, each instance sees both `default` TLSStore resources (from `traefik` and `traefik-mainframe` namespaces). This causes Traefik to silently fail loading the default certificate, falling back to its built-in self-signed "TRAEFIK DEFAULT CERT".

**Symptoms:**
- Browser shows self-signed certificate warning
- `openssl s_client` shows `issuer=CN=TRAEFIK DEFAULT CERT`
- TLSStore resources exist and reference valid secrets
- No errors in Traefik logs about TLSStore

**Fix:** Restrict `kubernetesCRD.namespaces` on each instance to only watch its own namespace plus any shared CRD namespaces (e.g., `authentik` for forward auth middleware):

```yaml
# traefik (akasha)
providers:
  kubernetesCRD:
    allowCrossNamespace: true
    namespaces:
      - traefik
      - authentik

# traefik-mainframe
providers:
  kubernetesCRD:
    allowCrossNamespace: true
    namespaces:
      - traefik-mainframe
      - authentik
```

### cert-manager DNS01 propagation fails

**Problem:** CoreDNS has a custom zone for `liberispat.com` (hairpin NAT) that resolves all subdomains to Traefik's ClusterIP (`10.43.0.100`). When cert-manager tries to verify DNS01 ACME challenges, it queries the cluster DNS, which returns the Traefik ClusterIP instead of the actual Cloudflare DNS records. cert-manager then tries to query `10.43.0.100:53` as a DNS server, which times out because Traefik is not a DNS server.

**Symptoms:**
- Certificates stuck in `InProgress` state
- cert-manager logs: `propagation check failed: dial tcp 10.43.0.100:53: i/o timeout`
- Challenges never complete

**Fix:** Configure cert-manager to use external recursive nameservers only:

```yaml
# infrastructure/controllers/cert-manager/helmrelease.yaml
values:
  extraArgs:
    - --dns01-recursive-nameservers-only
    - --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53
```

### Ingress tls.secretName not found

**Problem:** Ingress resources referencing `secretName: liberispat-wildcard-tls` in the `tls` block fail because the secret only exists in the Traefik namespaces, not in each app's namespace.

**Symptoms:**
- Traefik logs: `Error configuring TLS: secret <namespace>/liberispat-wildcard-tls does not exist`
- Self-signed cert served despite TLSStore being configured

**Fix:** Remove the `tls` block entirely from Ingress resources. The websecure entrypoint (`router.tls: "true"` annotation) and TLSStore default cert handle TLS without needing a per-Ingress secret reference.
