#!/bin/bash
set -e

VERSION="${1:-2.3.6}"
ARCH="${2:-amd64}"

echo "Installing zfs_exporter v${VERSION} for ${ARCH}..."

# Download binary
cd /tmp
curl -LO "https://github.com/pdf/zfs_exporter/releases/download/v${VERSION}/zfs_exporter-${VERSION}.linux-${ARCH}.tar.gz"
tar xzf "zfs_exporter-${VERSION}.linux-${ARCH}.tar.gz"

# Install binary
sudo cp "zfs_exporter-${VERSION}.linux-${ARCH}/zfs_exporter" /usr/local/bin/
sudo chmod +x /usr/local/bin/zfs_exporter

# Install systemd service
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "${SCRIPT_DIR}/zfs-exporter.service" /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable zfs-exporter
sudo systemctl start zfs-exporter

echo "zfs_exporter installed and running on port 9134"
echo "Verify with: curl http://localhost:9134/metrics"

# Cleanup
rm -rf "/tmp/zfs_exporter-${VERSION}.linux-${ARCH}"*
