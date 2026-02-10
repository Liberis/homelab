# NixOS configuration for zfs_exporter
# Add this to your NixOS configuration.nix or a separate module
{ pkgs, ... }:
{
  services.prometheus.exporters.zfs = {
    enable = true;
    port = 9134;
  };

  # Open firewall port (if needed for external access)
  networking.firewall.allowedTCPPorts = [ 9134 ];
}
