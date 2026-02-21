# Democratic-CSI Storage Configuration

## Current Setup

- **Driver**: `zfs-generic-nfs`
- **ZFS Host**: `192.168.10.12` (akasha)
- **User**: `democratic-csi` (SSH key auth, restricted shell access)
- **Datasets**: `tank/k8s/volumes` (data), `tank/k8s/snapshots` (snapshots)
- **Storage Classes**: `zfs-nfs` (default, async), `zfs-nfs-db` (sync, for databases)

## Security Model

ZFS commands use ZFS delegation (no sudo needed). chown/chmod/mkdir require sudo
with restricted wrappers in `/etc/democratic-csi/` (immutable, stored in nix store).

Sudoers allows:
- `zfs *` and `zpool *` via restricted wrapper (only `tank/k8s/*` datasets)
- `chown *`, `chmod *`, `mkdir *` via `/run/current-system/sw/bin/` paths

## Known Issues / Future Improvements

### Remove sudo for chown/chmod/mkdir

The current setup requires `sudoEnabled: true` in the driver config because
democratic-csi runs `sudo chown 0:0 <mountpoint>` after creating datasets.

**Option A: Remove permission-setting entirely**
- Remove `datasetPermissionsUser` and `datasetPermissionsGroup` from driver config
- Set `datasetPermissionsMode: "0777"` only
- Handle permissions via ZFS dataset properties at creation time (ZFS delegation)
- This eliminates all sudo requirements — democratic-csi only needs ZFS commands
- Trade-off: volumes are world-readable on the ZFS host (but access is controlled
  by Kubernetes RBAC and NFS export restrictions)

**Option B: Switch to iSCSI (`zfs-generic-iscsi`)**
- Block-level storage — K8s node handles filesystem and permissions locally
- No chown/chmod needed on ZFS host
- Trade-off: requires `targetcli` (iSCSI target) on ZFS host, which also needs sudo
- Trade-off: ReadWriteOnce only (no ReadWriteMany like NFS)
- Trade-off: more complex setup (iSCSI initiator on all K8s nodes, LIO on ZFS host)
- Trade-off: better performance for databases (block-level, no NFS overhead)

**Recommendation**: Option A is the simplest path to eliminating sudo entirely.
Option B makes sense if database performance becomes a concern.
