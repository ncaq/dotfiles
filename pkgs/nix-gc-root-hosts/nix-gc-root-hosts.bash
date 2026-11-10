#!/usr/bin/env bash
set -euo pipefail

# flakeに定義された全nixosConfigurationsとhomeConfigurationsの閉包を、
# GCから保護するGC rootを登録するスクリプト。
#
# どちらの属性集合も動的に列挙するため、
# flakeへ構成を追加するとこのスクリプトも自動で追従します。
# `nixOnDroidConfigurations`は列挙の対象に含めていません。
# QEMUエミュレーション経由のビルドが遅く、
# モデルファイルのような巨大なパスも含まれないためです。
#
# 環境変数:
#   STATE_DIRECTORY         GC rootのout-linkを置くディレクトリ。
#                           systemdの`StateDirectory`が設定します。
#   NIX_GC_ROOT_HOSTS_FLAKE 構成を列挙するflake。
#                           デフォルトはデプロイ時に配置される`/etc/nixos-flake`。

state_directory=${STATE_DIRECTORY:?STATE_DIRECTORY is not set}
flake=${NIX_GC_ROOT_HOSTS_FLAKE:-/etc/nixos-flake}

failed=0
names=()
installables=()

add() {
  names+=("$1")
  installables+=("$2")
}

# 一覧の取得に失敗した場合はここで中断します。
# 誤って後段のクリーンアップで既存のrootを消してしまわないようにするためです。
hostNames=$(nix eval --json "$flake#nixosConfigurations" --apply builtins.attrNames | jq -r '.[]')
homeSystems=$(nix eval --json "$flake#homeConfigurations" --apply builtins.attrNames | jq -r '.[]')

while IFS= read -r host; do
  add "nixos-$host" "$flake#nixosConfigurations.$host.config.system.build.toplevel"
done <<<"$hostNames"
while IFS= read -r system; do
  add "home-manager-$system" "$flake#homeConfigurations.$system.activationPackage"
done <<<"$homeSystems"

# 先に全installableを1回のnix buildへまとめて渡してウォームアップします。
# 1つずつビルドすると評価プロセスがその都度立ち上がる上に、
# ダウンロードとビルドが構成間で全く重なりません。
# まとめて渡せばNixのスケジューラが構成横断で並列に処理します。
# 失敗の検知は後段のout-linkで個別に行うため、ここでは失敗を無視します。
nix build --keep-going --no-link "${installables[@]}" || true

# ウォームアップでストアに成果物が揃っているため、
# ここの個別ビルドはout-linkを張るだけでほぼ即座に終わります。
for i in "${!names[@]}"; do
  if ! nix build "${installables[$i]}" --out-link "$state_directory/${names[$i]}"; then
    echo "failed to build ${installables[$i]}" >&2
    failed=1
  fi
done

# flakeから消えた構成のrootを削除して、
# 不要になった閉包をいつまでも保持し続けないようにします。
# `nix build`の中断などでシンボリックリンク以外の残骸が紛れ込んでいても、
# 削除に失敗して途中終了しないよう`rm -rf`で消します。
declare -A keep=()
for name in "${names[@]}"; do
  keep[$name]=1
done
shopt -s nullglob
for link in "$state_directory"/*; do
  name=${link##*/}
  if [[ -z ${keep[$name]:-} ]]; then
    rm -rf -- "$link"
  fi
done

exit "$failed"
