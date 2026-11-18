{ config, pkgs, ... }:
{
  # BIOS ONLY: change after checking your actual target disk.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  networking.hostName = "nixos-cloudstack";
  networking.useDHCP = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  time.timeZone = "UTC";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  # Add your own complete PUBLIC key, never a private key.
  users.users.root.openssh.authorizedKeys.keys = [ ];
  assertions = [ {
    assertion = config.users.users.root.openssh.authorizedKeys.keys != [ ];
    message = "Add your public SSH key to configuration.nix before building.";
  } ];

  environment.systemPackages = with pkgs; [ git curl jq nano ];
  system.stateVersion = "26.05";
}
