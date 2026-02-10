#!/bin/bash
set -e

VERSION="${1:-0.12.0}"
ARCH="${2:-amd64}"

echo "Installing smartctl_exporter v${VERSION} for ${ARCH}..."

# Download binary
cd /tmp
curl -LO "https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/smartctl_exporter-${VERSION}.linux-${ARCH}.tar.gz"
tar xzf "smartctl_exporter-${VERSION}.linux-${ARCH}.tar.gz"

# Install binary
sudo cp "smartctl_exporter-${VERSION}.linux-${ARCH}/smartctl_exporter" /usr/local/bin/
sudo chmod +x /usr/local/bin/smartctl_exporter

# Install systemd service
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp "${SCRIPT_DIR}/smartctl-exporter.service" /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable smartctl-exporter
sudo systemctl start smartctl-exporter

echo "smartctl_exporter installed and running on port 9633"
echo "Verify with: curl http://localhost:9633/metrics"

# Cleanup
rm -rf "/tmp/smartctl_exporter-${VERSION}.linux-${ARCH}"*
