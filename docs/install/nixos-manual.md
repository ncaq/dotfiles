# NixOS Installation (Manual Partitioning)

This guide describes the manual installation process with custom disk partitioning,
suitable for dual-boot setups where Windows is already installed.

## Prerequisites

- NixOS installation media booted
- Network and keyboard layout configured
- Terminal access
- (For dual boot) Windows partition already shrunk to make space

## Preparation

### For Windows Dual Boot

1. Shrink the Windows partition to free at least 100GB for NixOS (500GB+ recommended).
2. Create install media from <https://nixos.org/>
3. Boot install media
4. Configure network and keyboard layout
5. Open terminal

## Disk Partitioning

Create EFI partition for `/efi` (1GB) and root partition.
ESP will be mounted at `/efi`.

Use `lsblk` or `ls /dev/disk/by-id/` to identify your target disk.

```bash
sudo fdisk /dev/disk/by-id/your-disk
```

Create a new partition for the EFI Partition.
EFI Partition type is `EFI System` (`C12A7328-F81F-11D2-BA4B-00A0C93EC93B`)

```text
n
+1G
t
1
```

Create the root partition:

```text
n
```

Write changes:

```text
w
```

## File System Creation

```bash
sudo mkfs.vfat -F32 -n nixos-esp /dev/disk/by-id/your-disk-nixos-esp
sudo e2label /dev/disk/by-id/your-disk-root-for-crypt nixos-root-crypt
sudo cryptsetup luksFormat /dev/disk/by-id/nixos-root-crypt
sudo cryptsetup open /dev/disk/by-id/nixos-root-crypt nixos-root
sudo mkfs.btrfs /dev/mapper/nixos-root
sudo mount /dev/mapper/nixos-root /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@nix-store
sudo btrfs subvolume create /mnt/@var-log
sudo btrfs subvolume create /mnt/@snapshots
sudo umount /mnt
```

## Mount

```bash
sudo mount -o noatime,compress=zstd,subvol=@ /dev/mapper/nixos-root /mnt

sudo mkdir -p /mnt/efi
sudo mkdir -p /mnt/nix/store
sudo mkdir -p /mnt/var/log
sudo mkdir -p /mnt/.snapshots

sudo mount -o noatime,fmask=0077,dmask=0077 /dev/disk/by-label/nixos-esp /mnt/efi
sudo mount -o noatime,compress=zstd,subvol=@nix-store /dev/mapper/nixos-root /mnt/nix/store
sudo mount -o noatime,compress=zstd,subvol=@var-log /dev/mapper/nixos-root /mnt/var/log
sudo mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/nixos-root /mnt/.snapshots
```

## Installation

### `nixos-install`

```bash
NEW_HOST=please-input-new-hostname
nix-shell -p git

cd ~
git clone 'https://github.com/ncaq/dotfiles.git'
cd dotfiles

sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

Please reboot.

### `nixos-generate-config`

```zsh
cd ~
git clone 'https://github.com/ncaq/dotfiles.git'
cd dotfiles/nixos/host/${NEW_HOST}
sudo nixos-generate-config --show-hardware-config --no-filesystems > hardware-configuration.nix
```

## Notes

- This method provides full control over disk partitioning
- Suitable for dual-boot configurations with Windows
- Uses LUKS encryption for the root partition
- Uses btrfs with multiple subvolumes for better snapshot management
