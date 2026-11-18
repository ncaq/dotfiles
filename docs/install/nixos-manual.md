# NixOSのインストール(手動のパーティション分割)

ディスクのパーティションを手で切ってインストールする手順です。
Windowsが既にインストールされているマシンでデュアルブートにする場合に向いています。

プリインストールされたWindowsのパーティションの配置は機種ごとに違うので、
どの番号のパーティションをどの位置に作るのかは、
この手順書では決められません。
何を作るのかだけを書いて、
どこに作るのかは作業する人に任せます。

`nixos/host/creep`はこの方法でインストールしたホストです。
参考にしてください。

## 前提

- (デュアルブートの場合)Windowsのパーティションを縮めて空きを作ってある。
  NixOSには100GB以上、できれば500GB以上を空けます。
- NixOSのインストールメディアで起動している
- ネットワークとキーボードレイアウトを設定してある
- ターミナルを開ける

## パーティションの作成

最初に今の配置を確かめます。

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL
ls -l /dev/disk/by-id/
sudo fdisk -l /dev/disk/by-id/your-disk
```

空き領域に2つのパーティションを作ります。

- 1GiBのEFIシステムパーティション(ESP)。`/efi`にマウントします。
  Windowsが作ったESPは使い回しません。
  複数の世代のカーネルを置くには、
  たいてい小さすぎます。
- 残りの空き領域を全て使うルートパーティション

既存のWindowsのパーティションは、
消したり動かしたりしないでください。

```bash
sudo fdisk /dev/disk/by-id/your-disk
```

以下は`fdisk`のコマンドの説明で、
そのまま打ち込む手順ではありません。
`fdisk`は操作のたびにパーティションの番号やセクタを尋ねてきて、
正しい答えは配置によって変わります。

- `p`: パーティションテーブルを表示します。
  操作の前後で毎回確かめます。
- `n`: パーティションを作ります。
  ESPは、
  番号と開始セクタを既定のままにして、
  終了セクタに`+1G`と答えます。
  ルートパーティションは、
  全て既定のままにすると残りの空き領域を使います。
- `t`: パーティションの種類を変えます。
  作ったESPを選んで、
  種類を`1`(`EFI System`)にします。
  ルートパーティションは`Linux filesystem`のままで構いません。
- `w`: 変更を書き込んで終了します。
  それまでは何も書き込まれません。
- `q`: 書き込まずに終了します。

作った2つのパーティションを`/dev/disk/by-id/`から探して、
変数に入れます。
以降の手順はこの変数を使います。

```bash
ESP_PART=/dev/disk/by-id/your-disk-partN
ROOT_PART=/dev/disk/by-id/your-disk-partM
lsblk -o NAME,SIZE,FSTYPE,LABEL "$ESP_PART" "$ROOT_PART"
```

サイズが合っていることと、
どちらにもまだファイルシステムが無いことを確かめてください。
間違ったパーティションをフォーマットするとWindowsが壊れます。

## ファイルシステムの作成

ホストの設定はパーティションをラベルで参照するので、
ラベルは`nixos-esp`と`nixos-root-crypt`にする必要があります。

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

`cryptsetup luksFormat`はパスフレーズを尋ねてきます。
後でFIDO2のデバイスを登録しても、
予備の手段としてパスフレーズは控えておいてください。

## マウント

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

## ホストの設定

```bash
NEW_HOST=please-input-new-hostname
export NIX_CONFIG="experimental-features = flakes nix-command"
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
```

ホストが既にこのリポジトリに定義されていて、
ハードウェアも変わっていないなら、
[インストール](#インストール)へ進んでください。

新しいホストの場合は、
`nixos-install`がビルドする前に設定が存在している必要があります。
インストールメディアの上で作ります。

- `flake.nix`の`hostInfo`にホストを足します。
- `nixos/host/${NEW_HOST}.nix`と`nixos/host/${NEW_HOST}/`を作ります。
  `nixos/host/creep.nix`と`nixos/host/creep/`からコピーして、
  そのマシンに固有の部分を消します。
- `boot.nix`のWindowsへのチェインロードのエントリを書き換えます。
  Windowsが作ったESPをGPTのパーティションGUIDで指しています。
  GUIDは`lsblk -o NAME,SIZE,FSTYPE,PARTUUID`で調べられます。

ハードウェアの設定はインストールメディアから生成します。
ファイルシステムは`disk.nix`で宣言するので除きます。

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config --no-filesystems \
  > "nixos/host/${NEW_HOST}/hardware-configuration.nix"
```

flakeにはGitが追跡しているファイルしか見えません。
新しいファイルをステージングしないと、
ビルドがファイルを見つけられません。

```bash
nix run 'nixpkgs#git' -- add flake.nix nixos/host
```

## インストール

```bash
sudo nixos-install --flake ".#${NEW_HOST}" --root /mnt
```

インストールしたシステムには、
インストールメディアの上で行った変更が入っていません。
新しいホストを作った場合は、
再起動する前にリポジトリを新しいシステムのユーザのホームへコピーしてください。
インストールメディアのユーザと新しいシステムのユーザはuidが同じなので、
所有者はそのままで合います。

```bash
sudo cp -a . /mnt/home/ncaq/dotfiles
```

再起動してください。

## 最初の起動の後

新しいホストを作った場合は、
ログインしてから`~/dotfiles`で変更をコミットします。

### FIDO2

`nixos/host/creep/boot.nix`のようにホストが`fido2-device=auto`を設定していると、
YubiKeyなどのFIDO2のデバイスでルートパーティションを復号できます。
デバイスを登録するまでは、
起動のたびにパスフレーズを尋ねられます。

```bash
sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-label/nixos-root-crypt
```

## 補足

- ディスクのパーティションを全て自分で決められます
- Windowsとのデュアルブートの構成に向いています
- ルートパーティションはLUKSで暗号化します
- スナップショットを管理しやすいように、btrfsを複数のサブボリュームに分けて使います
