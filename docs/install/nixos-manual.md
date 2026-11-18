# NixOS Installation (Manual Partitioning)

This guide describes the manual installation process with custom disk partitioning,
suitable for dual-boot setups where Windows is already installed.

The partition layout of a preinstalled Windows differs from machine to machine,
so this guide cannot tell you which partition numbers or offsets to use.
It describes what to create,
and leaves where to create it to you.

`nixos/host/creep` is a host installed this way.
Use it as a reference.

## Prerequisites

- (For dual boot) Windows partition already shrunk to make space.
  Free at least 100GB for NixOS (500GB+ recommended).
- NixOS installation media booted
- Network and keyboard layout configured
- Terminal access

## Disk Partitioning

Look at the current layout first.

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL
ls -l /dev/disk/by-id/
sudo fdisk -l /dev/disk/by-id/your-disk
```

Create two partitions in the free space.

- An EFI System Partition of 1GiB, which will be mounted at `/efi`.
  Do not reuse the ESP that Windows created.
  It is usually too small for the kernels of multiple generations.
- A root partition that takes the rest of the free space.

Do not delete or move the existing Windows partitions.

```bash
sudo fdisk /dev/disk/by-id/your-disk
```

The following is a guide to the `fdisk` commands, not a script to type as is.
`fdisk` asks for a partition number and sectors on each step,
and the right answers depend on the layout.

- `p` prints the partition table. Use it before and after each step.
- `n` creates a partition.
  For the ESP, accept the default partition number and first sector,
  and answer `+1G` for the last sector.
  For the root partition, accept all defaults to use the rest of the free space.
- `t` changes the type of a partition.
  Select the ESP you just created and set the type to `1` (`EFI System`).
  The root partition can stay `Linux filesystem`.
- `w` writes the changes and exits. Nothing is written until then.
- `q` exits without writing.

Find the two new partitions under `/dev/disk/by-id/` and keep them in variables.
The following steps use these variables.

```bash
ESP_PART=/dev/disk/by-id/your-disk-partN
ROOT_PART=/dev/disk/by-id/your-disk-partM
lsblk -o NAME,SIZE,FSTYPE,LABEL "$ESP_PART" "$ROOT_PART"
```

Check the sizes and that neither of them has a file system yet.
Formatting the wrong partition destroys Windows.

## File System Creation

The host configuration refers to the partitions by label,
so the labels must be `nixos-esp` and `nixos-root-crypt`.

```bash
sudo mkfs.vfat -F32 -n nixos-esp "$ESP_PART"
sudo cryptsetup luksFormat --label nixos-root-crypt "$ROOT_PART"
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

`cryptsetup luksFormat` asks for a passphrase.
Keep it even if you enroll a FIDO2 device later, as the fallback.

## Mount

```bash
sudo mount -o noatime,compress=zstd,subvol=@ /dev/mapper/nixos-root /mnt

sudo mkdir -p /mnt/efi
sudo mkdir -p /mnt/nix/store
sudo mkdir -p /mnt/swap
sudo mkdir -p /mnt/var/log
sudo mkdir -p /mnt/.snapshots

sudo mount -o noatime,fmask=0077,dmask=0077 /dev/disk/by-label/nixos-esp /mnt/efi
sudo mount -o noatime,compress=zstd,subvol=@nix-store /dev/mapper/nixos-root /mnt/nix/store
sudo mount -o noatime,subvol=@swap /dev/mapper/nixos-root /mnt/swap
sudo mount -o noatime,compress=zstd,subvol=@var-log /dev/mapper/nixos-root /mnt/var/log
sudo mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/nixos-root /mnt/.snapshots
```

## Host Configuration

```bash
NEW_HOST=please-input-new-hostname
export NIX_CONFIG="experimental-features = flakes nix-command"
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
```

If the host is already defined in this repository and the hardware has not changed,
skip to [Installation](#installation).

For a new host, the configuration has to exist before `nixos-install` can build it.
Create it on the installation media.

- Add the host to `hostInfo` in `flake.nix`.
- Create `nixos/host/${NEW_HOST}.nix` and `nixos/host/${NEW_HOST}/`.
  Copy them from `nixos/host/creep.nix` and `nixos/host/creep/`,
  and remove what is specific to that machine.
- Rewrite the Windows chainload entry in `boot.nix`.
  It points to the ESP that Windows created by its GPT partition GUID.
  Find the GUID with `lsblk -o NAME,SIZE,FSTYPE,PARTUUID`.

Generate the hardware configuration from the installation media.
The file systems are declared in `disk.nix`, so leave them out.

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config --no-filesystems \
  > "nixos/host/${NEW_HOST}/hardware-configuration.nix"
```

A flake only sees files that Git tracks.
Stage the new files, or the build will not find them.

```bash
git add flake.nix nixos/host
```

## Installation

```bash
sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

The installed system does not have the changes made on the installation media.
If you created a new host, copy the repository into the new system before rebooting.
Commit the changes after the first boot.

```bash
sudo cp -a . /mnt/root/dotfiles
```

Please reboot.

## After the First Boot

### FIDO2

The root partition can be unlocked with a FIDO2 device such as a YubiKey
when the host sets `fido2-device=auto` like `nixos/host/creep/boot.nix`.
Until a device is enrolled, the passphrase is asked on every boot.

```bash
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-label/nixos-root-crypt
```

## Notes

- This method provides full control over disk partitioning
- Suitable for dual-boot configurations with Windows
- Uses LUKS encryption for the root partition
- Uses btrfs with multiple subvolumes for better snapshot management
