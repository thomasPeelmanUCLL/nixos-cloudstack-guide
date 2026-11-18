# NixOS on Apache CloudStack

A plain, flake-based NixOS server and a manual installation guide. No Ollama, AI models, Kubernetes agents, or application services.

## Scope

The worked installation used an x86_64 KVM VM, legacy BIOS, an MBR partition table, and one ext4 root partition on /dev/sda. That installation reached a successful first boot. This extracted plain-server configuration has not itself been build-tested or deployed; validate it before use. CloudStack alone does not determine the guest hypervisor, disk name, firmware, or network configuration.

The commands below target BIOS only. If your firmware check says UEFI, STOP: this partition layout and GRUB configuration are not the UEFI recipe. Use the NixOS manual to create and mount an EFI system partition and choose the appropriate bootloader. Other hypervisors and prebuilt CloudStack template imports are outside this guide.

## Before starting

- Permission to create a VM and attach/detach a bootable ISO in your CloudStack project.
- An x86_64 NixOS 26.05 minimal installer ISO. Obtain its URL and checksum from the official NixOS download/release pages. Confirm ISO registration rules with your provider; do not guess a URL.
- A persistent root disk, CloudStack console access, working outbound DNS/HTTPS, and your own SSH key pair.
- Restrict inbound TCP 22 to your management IP or VPN in CloudStack security groups or network ACLs. Depending on the network offering, remote access may require a public IP and port forwarding. No additional inbound application ports are needed.
- Keep private keys, passwords, API tokens, and console URL tokens out of Git and screenshots.

This is a manual ISO installation, not CloudStack API provisioning. No cloud-init, metadata key injection, provider password reset integration, or reusable VM template is configured.

## 1. Create and boot the VM

Register the installer through your provider's ISO interface, using the provider-approved OS type and bootable settings. Create a VM with a suitable compute offering and persistent disk, select the installer ISO, start it, and open its console. Labels and permissions vary across CloudStack installations.

At the installer prompt:

```sh
sudo -i
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
ip -br address
ip route
curl -I --max-time 15 https://cache.nixos.org
```

Proceed only for BIOS. Identify the actual persistent disk by its size and device type; optical ISO drives and the live filesystem are not install targets. An HTTP 200 response confirms that particular HTTPS request worked, not that all future downloads will succeed. Do not copy someone else's IP address or interface configuration.

## 2. Partition the disk: destructive

WARNING: the following commands DESTROY DATA on /dev/sda. Run them only after confirming /dev/sda is the intended disk and its entire contents may be erased. If your disk is named differently, adapt every disk/partition reference and the GRUB setting; partition naming conventions differ. Stop on any error.

This simple BIOS layout uses one root partition, with /boot on the root filesystem and no swap or encryption.

```sh
parted --script /dev/sda mklabel msdos
parted --script /dev/sda mkpart primary ext4 1MiB 100%
parted --script /dev/sda set 1 boot on
udevadm settle
mkfs.ext4 -L nixos /dev/sda1
mount /dev/disk/by-label/nixos /mnt
nixos-generate-config --root /mnt
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
cat /mnt/etc/nixos/hardware-configuration.nix
```

Verify the intended ext4 partition is mounted at /mnt. Keep the generated hardware file: it contains your actual root UUID and drivers. Do not substitute another user's UUID or hardware file.

## 3. Clone this public repository

No GitHub login is needed to clone this public repository. In the installer:

```sh
nix-shell -p git nano
# Continue inside the new shell:
git clone https://github.com/thomasPeelmanUCLL/nixos-cloudstack-guide.git /mnt/etc/nixos/cloudstack
cd /mnt/etc/nixos/cloudstack
cp /mnt/etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
nano configuration.nix
```

The repository deliberately does not supply hardware-configuration.nix. You must generate and copy it before evaluating the flake.

In configuration.nix, confirm boot.loader.grub.device names the WHOLE BIOS boot disk (for example /dev/sda, not /dev/sda1). Set the hostname and add your own public key:

```nix
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 YOUR_COMPLETE_PUBLIC_KEY your-comment"
];
```

Replace the existing empty assignment; do not add a second one. The complete public key must be one line inside quotes. On your own computer, an existing key may be displayed with `cat ~/.ssh/id_ed25519.pub`. If you have no key pair, create one locally with `ssh-keygen -t ed25519` without overwriting an existing key. Keep the private key on your computer. On Windows PowerShell, use `Get-Content $HOME\.ssh\id_ed25519.pub` to display the public key.

The configuration intentionally fails its build until a key is supplied. Root SSH is key-only; password login over SSH is disabled. The installer's root-password prompt sets a password for console recovery, not password-based SSH.

DHCP is the default. If your provider requires static networking, configure its actual interface, address/prefix, gateway, and DNS before building. Installer connectivity does not guarantee the installed system will inherit the same network configuration. Do not enable competing network managers without understanding their interaction.

## 4. Lock dependencies and build

```sh
git add configuration.nix hardware-configuration.nix
nix --extra-experimental-features 'nix-command flakes' flake lock
git add flake.lock
nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.cloudstack.config.system.build.toplevel --no-link -L
# Immediately after the build:
echo $?
```

Proceed only if the build succeeds (exit code 0). These Git commands stage local files; they do not upload or commit anything. A dirty-tree warning is expected with local changes. Staging ensures newly generated files are included in the Git-backed flake. Generate flake.lock with Nix; do not invent revisions/hashes. Review and commit the generated lock in your own configuration repository for reproducibility.

Build success is not proof of boot success. Investigate warnings that may affect your boot path rather than assuming all warnings are harmless.

## 5. Install

```sh
nixos-install --root /mnt --flake .#cloudstack
```

Choose a strong root password when prompted; keep it private. Wait for successful completion, including bootloader installation. Stop and investigate errors before shutting down. If installation fails, fix the configuration and rerun installation; do not repartition as a troubleshooting shortcut.

```sh
poweroff
```

In CloudStack, wait for the VM to stop, detach the NixOS INSTALLER ISO, start the VM, and reopen the console. Do not detach a separate provider config drive. Never destroy the instance or delete its root volume to remove an ISO.

## 6. Verify the first boot

Log in through the console as root using the password you set:

```sh
hostname
findmnt /
lsblk -f
ip -br address
ip route
systemctl --failed
systemctl status sshd --no-pager -l
curl -I --max-time 15 https://cache.nixos.org
```

Confirm the hostname is nixos-cloudstack (unless changed) and / is backed by the installed disk, not the installer live filesystem. From a computer with a working route to the VM, test `ssh root@YOUR_VM_ADDRESS` with your matching private key. Verify the host key through a trusted channel. Keep console access available while testing. A private IP is not automatically reachable from the public internet.

## 7. Maintain the installed configuration

After reboot, the repository is at /etc/nixos/cloudstack, NOT /mnt/etc/nixos/cloudstack. The generated /etc/nixos/configuration.nix outside that directory is not the flake used here. Always specify the flake path:

```sh
cd /etc/nixos/cloudstack
nixos-rebuild build --flake .#cloudstack
nixos-rebuild switch --flake .#cloudstack
```

Review changes before activation. Before updating dependencies, keep working boot generations and console access, then:

```sh
nix flake update
nixos-rebuild build --flake .#cloudstack
nixos-rebuild switch --flake .#cloudstack
```

Commit reviewed configuration and lock changes to your own repository; do not attempt to push to this guide without maintainer permission. Do not blindly change system.stateVersion when updating nixpkgs: it controls compatibility defaults, not the package release. Protect VM-specific files and never commit secrets, even to a private repository.

## Troubleshooting

- Installer welcome screen after restart: check whether the installer ISO is still attached and whether the VM boot order selects the disk.
- Missing hardware file: generate it with the root partition mounted at /mnt, copy it into the repository, and stage it with git add.
- Missing public-key assertion: replace the empty key list with your complete public key.
- SSH refused/timed out: check sshd from the console, the VM address/route, CloudStack ACLs/security groups/port forwarding, and the NixOS firewall. Do not disable all firewalls as a shortcut.
- SSH permission denied: use root and the private key matching the configured public key. Password-based SSH is deliberately disabled.
- DNS failure: inspect addresses, routes, resolver configuration, and current name resolution. One early startup warning alone is not proof of a persistent DNS fault.
- GRUB/boot failure: use console logs to check firmware, disk naming, root UUID, and initrd storage drivers. Preserve the generated hardware configuration. Use the installer ISO for recovery; do not erase the disk again.
- No clipboard in the console: use the console's paste facility if available, or set up restricted temporary SSH with a public key. Do not expose empty-password login.

## Official documentation

- NixOS manual: https://nixos.org/manual/nixos/stable/
- NixOS installation guide: https://wiki.nixos.org/wiki/NixOS_Installation_Guide
- NixOS flakes: https://wiki.nixos.org/wiki/Flakes
- Apache CloudStack administration: https://docs.cloudstack.apache.org/en/latest/adminguide/

Provider-specific VM creation, ISO registration, network offerings, and hypervisor details must be checked against your own environment.
