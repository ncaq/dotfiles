#!/usr/bin/env bash
set -euo pipefail

# gitがPATHにない場合gitをPATHに追加して再実行。
# Nix-on-Droidの初期環境などではgitがインストールされていないため必要。
if ! command -v git &>/dev/null; then
  # gitがないとflakeの読み込みも出来ないのでnixpkgsの生の使用はやむを得ない。
  exec nix shell 'nixpkgs#git' --command "$0" "$@"
fi

# aarch64-linux用のbinfmtエミュレーションをブートストラップします。
# NixOS設定にboot.binfmt.emulatedSystemsが含まれていても、
# 初回インストール時はbinfmtがまだ有効になっていないため、
# aarch64-linux derivationのビルドに失敗します(chicken-and-egg問題)。
# この関数で一時的にbinfmtを設定することでnixos-rebuildを成功させます。
# リビルド後はNixOSが正式なbinfmt設定を管理します。
bootstrap_binfmt_aarch64() {
  echo "aarch64 binfmtをブートストラップ中..."

  # binfmt_miscファイルシステムがマウントされていなければマウント
  if ! test -e /proc/sys/fs/binfmt_misc/register; then
    sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
  fi

  # qemu-userをビルド
  local qemu_user
  qemu_user=$(nix build .#qemu-user --print-out-paths --no-link)

  # カーネルにaarch64 binfmtハンドラを登録
  # Fフラグ: 登録時にインタープリタをカーネルにロードするため、
  # Nixサンドボックス内でも追加のパス設定なしで動作します。
  # NixOSのnixos/lib/binfmt-magics.nixからのELFマジックバイトとマスク。
  local magic mask interpreter
  magic='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
  magic+='\x02\x00\xb7\x00'
  mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\x00\xff'
  mask+='\xfe\xff\xff\xff'
  interpreter="${qemu_user}/bin/qemu-aarch64"
  printf '%s\n' ":aarch64-linux:M:0:${magic}:${mask}:${interpreter}:F" |
    sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null

  # NixOS管理のnix.confを一時的にコピーしてextra-platformsを追加します。
  # nixos-rebuild後にNixOSの活性化スクリプトが正しいシンボリックリンクを復元します。
  local nix_conf="/etc/nix/nix.conf"
  # シンボリックリンクの場合のみコピーで実体化する(既に通常ファイルならスキップ)
  if [ -L "$nix_conf" ]; then
    sudo cp --remove-destination "$(readlink -f "$nix_conf")" "$nix_conf"
  fi
  echo "extra-platforms = aarch64-linux" | sudo tee -a "$nix_conf" >/dev/null
  # Nixサンドボックス内でQEMUとその依存ライブラリにアクセスできるようにします。
  # Fフラグでインタープリタ自体はロード済みですが、
  # QEMUの動的リンカがサンドボックス内で共有ライブラリを解決する必要があります。
  local sandbox_paths
  sandbox_paths=$(nix path-info -r "$qemu_user" | tr '\n' ' ')
  printf 'extra-sandbox-paths = %s\n' "$sandbox_paths" |
    sudo tee -a "$nix_conf" >/dev/null
  sudo systemctl restart nix-daemon

  echo "binfmtブートストラップ完了"
}

if [ -f /etc/NIXOS ]; then
  # seminarホストはaarch64 microVMをビルドするためbinfmtが必要です。
  # binfmtが未設定の場合、nixos-rebuildの前にブートストラップします。
  if [ "$(hostname)" = "seminar" ] && ! test -e /proc/sys/fs/binfmt_misc/aarch64-linux; then
    bootstrap_binfmt_aarch64
  fi
  sudo nixos-rebuild switch --flake ".#$(hostname)"
elif [ -n "${TERMUX_VERSION:-}" ]; then
  nix-on-droid switch --flake "."
else
  case $(uname -m) in
  x86_64)
    home-manager --flake ".#x86_64-linux" -b "hm-bak" switch
    ;;
  aarch64)
    home-manager --flake ".#aarch64-linux" -b "hm-bak" switch
    ;;
  *)
    echo "未対応のプラットフォーム: $(uname -s)-$(uname -m)"
    exit 1
    ;;
  esac
fi
