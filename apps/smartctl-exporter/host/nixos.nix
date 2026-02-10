# NixOS configuration for smartctl_exporter
# Add this to your NixOS configuration.nix or a separate module
{
  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9633;
    # Scan interval in seconds
    extraFlags = [ "--smartctl.interval=60s" ];
  };

  # Open firewall port (if needed for external access)
  networking.firewall.allowedTCPPorts = [ 9633 ];
}
