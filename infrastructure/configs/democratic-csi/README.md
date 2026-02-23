# Democratic-CSI Storage Configuration

## Current Setup

- **Driver**: `zfs-generic-nfs`
- **ZFS Host**: `akasha` (192.168.10.12)
- **Execution**: Local (controller pod pinned to akasha via nodeSelector)
- **Datasets**: `tank/k8s/volumes` (data), `tank/k8s/snapshots` (snapshots)
- **Storage Classes**: `zfs-nfs` (default, async), `zfs-nfs-db` (sync, for databases)

## How It Works

The controller pod is pinned to `akasha` (the ZFS host) using a nodeSelector.
The host root filesystem is mounted at `/host` inside the container, and the
container's built-in chroot wrappers (`/usr/local/bin/zfs`, etc.) execute
`chroot /host` to access the host's ZFS binaries directly.

This eliminates the need for SSH keys, a dedicated user, or Vault secrets.

## Troubleshooting

1. Verify the controller is running on akasha:
   ```
   kubectl get pods -n democratic-csi -o wide
   ```

2. Check controller logs:
   ```
   kubectl logs -n democratic-csi -l app.kubernetes.io/csi-role=controller -c csi-driver
   ```

3. Test provisioning:
   ```
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: test-pvc
   spec:
     storageClassName: zfs-nfs
     accessModes: [ReadWriteMany]
     resources:
       requests:
         storage: 1Gi
   EOF
   ```
