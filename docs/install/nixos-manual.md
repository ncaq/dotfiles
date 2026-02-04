# NixOS Installation (Manual Partitioning)

This guide describes the manual installation process with custom disk partitioning, suitable for dual-boot setups with Windows.

## Prerequisites

- NixOS installation media booted
- Network and keyboard layout configured
- Terminal access
- (For dual boot) Windows partition already shrunk to make space

## Preparation

### For Windows Dual Boot

1. Shrink the disk partition in Windows to free at least 20GB for NixOS (50GB+ recommended)
2. Create install media from [Nix & NixOS | Declarative builds and deployments](https://nixos.org/)
3. Boot install media
4. Configure network and keyboard layout
5. Open terminal

## Disk Partitioning

Create XBOOTLDR partition for `/boot` (1GB) and root partition.
Following Boot Loader Specification, ESP will be mounted at `/efi` and XBOOTLDR at `/boot`.

Use `lsblk` or `ls /dev/disk/by-id/` to identify your target disk.

```console
sudo fdisk /dev/disk/by-id/your-disk-id
```

Create a new partition for the boot loader (XBOOTLDR).
XBOOTLDR type is `Linux extended boot` (`BC13C2FF-59E6-4262-A352-B275FD6F7172`).

```
n
+1G
t
142
```

Create the root partition:

```
n
```

Write changes:

```
w
```

## File System Creation

```console
sudo mkfs.vfat -F32 -n nixos-boot /dev/disk/by-id/your-disk-id-of-boot
sudo e2label /dev/disk/by-id/your-disk-id-of-root-for-crypt nixos-root-crypt
sudo cryptsetup luksFormat /dev/disk/by-label/nixos-root-crypt
sudo cryptsetup open /dev/disk/by-label/nixos-root-crypt nixos-root
sudo mkfs.btrfs /dev/mapper/nixos-root
sudo mount /dev/mapper/nixos-root /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@nix-store
sudo btrfs subvolume create /mnt/@swap
sudo btrfs subvolume create /mnt/@var-log
sudo btrfs subvolume create /mnt/@snapshots
sudo umount /mnt
```

## Mount

```console
sudo mount -o noatime,compress=zstd,subvol=@ /dev/mapper/nixos-root /mnt

sudo mkdir -p /mnt/efi
sudo mkdir -p /mnt/boot
sudo mkdir -p /mnt/nix/store
sudo mkdir -p /mnt/swap
sudo mkdir -p /mnt/var/log
sudo mkdir -p /mnt/.snapshots

sudo mount -o noatime,fmask=0077,dmask=0077 /dev/disk/by-label/nixos-boot /mnt/boot
sudo mount -o noatime,fmask=0077,dmask=0077 /dev/disk/by-label/your-disk-label-of-efi-system /mnt/efi
sudo mount -o noatime,compress=zstd,subvol=@nix-store /dev/mapper/nixos-root /mnt/nix/store
sudo mount -o noatime,subvol=@swap /dev/mapper/nixos-root /mnt/swap
sudo mount -o noatime,compress=zstd,subvol=@var-log /dev/mapper/nixos-root /mnt/var/log
sudo mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/nixos-root /mnt/.snapshots
```

## Installation

### `nixos-install`

```console
NEW_HOST=please-input-new-hostname
nix-shell -p git

cd ~
git clone 'https://github.com/ncaq/dotfiles.git'
cd dotfiles

sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

### `nixos-generate-config`

```console
sudo nixos-generate-config --show-hardware-config --no-filesystems > ~/dotfiles/nixos/host/${NEW_HOST}/hardware-configuration.nix
```

## Notes

- This method provides full control over disk partitioning
- Suitable for dual-boot configurations with Windows
- Uses LUKS encryption for the root partition
- Uses btrfs with multiple subvolumes for better snapshot management
