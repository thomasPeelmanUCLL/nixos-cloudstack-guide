{
  description = "Plain NixOS server on Apache CloudStack";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.cloudstack = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ./hardware-configuration.nix ];
    };
  };
}
