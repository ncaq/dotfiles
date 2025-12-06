# dotfiles

My main configuration files.

It's managed by
[NixOS | Declarative builds and deployments](https://nixos.org/) and
[home-manager](https://github.com/nix-community/home-manager).

# Note

> [!NOTE]
> My default `${USER}` is `ncaq`.
> I haven't tested with other usernames.
> I have hard-coded the username.
> Maybe, if you want to use other username, you need to change code.

# Initial

## NixOS

### Manual for with Windows dual boot

#### Preparation

Shrink the disk partition.

Create install media from [Nix & NixOS | Declarative builds and deployments](https://nixos.org/).

Boot install media.

Setting network and keyboard layout.

Open terminal.

#### Disk Partitioning

Create XBOOTLDR partition for `/boot` (1GB) and root partition.
Following Boot Loader Specification, ESP will be mounted at `/efi` and XBOOTLDR at `/boot`.

```console
sudo fdisk /dev/disk/by-id/your-disk-id
```

create a new partition for the boot loader(XBOOTLDR).
XBOOTLDR type is `Linux extended boot`(`BC13C2FF-59E6-4262-A352-B275FD6F7172`).

```
n
+1G
t
142
```

```
n
```

```
w
```

#### File System Creation

```console
sudo mkfs.vfat -F32 -n nixos-boot /dev/disk/by-id/your-disk-id-of-boot
sudo e2label /dev/disk/by-id/your-disk-id-of-root-for-crypt nixos-root-crypt
sudo cryptsetup luksFormat /dev/disk/by-id/nixos-root-crypt
sudo cryptsetup open /dev/disk/by-id/nixos-root-crypt nixos-root
sudo mkfs.btrfs /dev/mapper/nixos-root
sudo mount /dev/mapper/nixos-root /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@nix-store
sudo btrfs subvolume create /mnt/@swap
sudo btrfs subvolume create /mnt/@var-log
sudo btrfs subvolume create /mnt/@snapshots
sudo umount /mnt
```

#### Mount

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

#### `nixos-install`

```console
NEW_HOST=please-input-new-hostname
nix-shell -p git

cd ~
git clone 'https://github.com/ncaq/dotfiles.git'
cd dotfiles

sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

#### `nixos-generate-config`

```console
sudo nixos-generate-config --show-hardware-config --no-filesystems > ~/dotfiles/nixos/host/${NEW_HOST}/hardware-configuration.nix
```

### Automatic

```zsh
NEW_HOST=please-input-new-hostname
nix --extra-experimental-features 'flakes nix-command' run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
sudo nix --experimental-features 'flakes nix-command' run github:nix-community/disko/latest -- --mode format,mount --flake ".#${NEW_HOST}"
sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

Please reboot.

## Non NixOS(home-manager standalone)

```zsh
nix run home-manager/release-25.11 -- --flake ".#${USER}" init --switch .
```

# Rebuild

## NixOS

```zsh
sudo nixos-rebuild switch --flake ".#$(hostname)"
```

## Non NixOS(home-manager standalone)

```zsh
home-manager --flake ".#${USER}" switch
```

# Format

```zsh
nix fmt
```

# Check

## Static

```zsh
nix flake check
```

## Dynamic

```zsh
nix run github:nix-community/home-manager -- switch --flake ".#${USER}" -n -b backup
```

# Policy

As a general approach,
I'm managing everything possible with home-manager.
I only use the NixOS configuration part when absolutely necessary.

# Directory Structure

## [flake.nix](./flake.nix)

The entry point of the flake.

## [home/](./home/)

The home-manager configuration files.

`home/` contains the home-manager configuration files.

### [home/link.nix](./home/link.nix), [home/linked/](./home/linked/)

Create symbolic links from filepath.
`link.nix` is the program that creates them.
`linked/` contains the linked files.

### [home/package/](./home/package/)

To install packages.

## [nixos/](./nixos/)

NixOS configuration files.

## [git-hooks/](./git-hooks/)

These are my Git global hooks.

It's semi standalone.
I might move it to a separate repository because it's unrelated to Nix.

# Separated dotfiles

- [ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
- [ncaq/.percol.d](https://github.com/ncaq/.percol.d)
- [ncaq/.xkeysnail: My xkeysnail config](https://github.com/ncaq/.xkeysnail)
- [ncaq/.xmonad](https://github.com/ncaq/.xmonad)
- [ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
- [ncaq/keyhac-config](https://github.com/ncaq/keyhac-config)
- [ncaq/surfingkeys-config: My Surfingkeys config](https://github.com/ncaq/surfingkeys-config)
- [ncaq/winconf: My Windows configuration files](https://github.com/ncaq/winconf)
