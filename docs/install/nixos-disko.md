# diskoを使ったNixOSのインストール(自動)

diskoを使って自動でインストールする手順です。

## 前提

- NixOSのインストールメディアで起動している
- ネットワークとキーボードレイアウトを設定してある
- ターミナルを開ける

## インストールの手順

```bash
NEW_HOST=please-input-new-hostname
export NIX_CONFIG="experimental-features = flakes nix-command"
nix run 'nixpkgs#git' -- clone https://github.com/ncaq/dotfiles.git
cd dotfiles
sudo -E nix run '.#disko' -- --mode format,mount --flake ".#${NEW_HOST}"

# nixos-installの回避策

sudo mkdir -p /mnt/build

df -h /
mount | grep -iE 'rw-store|overlay|/nix'
sudo mount -o remount,size=48G /nix/.rw-store

nix build "path:$PWD#nixosConfigurations.${NEW_HOST}.config.system.build.toplevel" \
  --out-link /mnt/build/toplevel \
  --extra-experimental-features "nix-command flakes"

TOPLEVEL=$(readlink -f /mnt/build/toplevel)
sudo nix copy --to /mnt "$TOPLEVEL" --no-check-sigs \
  --extra-experimental-features "nix-command flakes"

sudo nixos-install --system "$TOPLEVEL" --root /mnt --no-channel-copy
```

インストールが終わったら再起動してください。

## 補足

- ディスクのパーティション分割とフォーマットはdiskoが自動で行います
- ディスクの構成はflakeの設定で定義しています
- 手動でのパーティション分割は要りません
