# Unbound DNS Resolver

## Current Setup

- **Image**: `klutchell/unbound`
- **ClusterIP**: `10.43.0.53` (static)
- **Node**: `mainframe`
- **Role**: Recursive resolver, upstream for AdGuard Home

### DNS Chain

```
Clients -> AdGuard Home (192.168.10.254) -> Unbound (10.43.0.53) -> Internet
```

## EDNS Buffer Size (VPN Fragmentation Fix)

### Problem

When routing network traffic through a VPN, certain DNSSEC-signed domains (e.g. `skroutz.gr`) fail with `SERVFAIL`. This happens because:

1. VPN tunnels reduce the effective MTU (typically from 1500 to ~1280-1420 bytes) due to encapsulation overhead
2. DNSSEC-signed DNS responses are significantly larger than unsigned ones (crypto signatures)
3. Large UDP DNS responses exceed the VPN MTU, causing IP fragmentation
4. Fragmented UDP packets are frequently dropped by middleboxes and VPN tunnels
5. The query fails with SERVFAIL since the response never arrives intact

### Solution

Two settings in the unbound `server:` config cap UDP DNS packet sizes to 1232 bytes (safe for all tunnel MTUs per [DNS Flag Day 2020](https://dnsflagday.net/2020/)):

- **`edns-buffer-size: 1232`** - Advertises to upstream authoritative servers that unbound can only receive UDP responses up to 1232 bytes. Larger responses automatically retry over TCP.
- **`max-udp-size: 1232`** - Caps the size of UDP responses unbound sends back to clients (AdGuard). Anything larger triggers TCP fallback.

AdGuard is already configured with `tcp://10.43.0.53:53` as an upstream, so TCP fallback works seamlessly.
