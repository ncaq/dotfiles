# cdn.ncaq.netのステージングから配信ディレクトリへ、配信してよいものだけを写すコマンド。
#
# 同じディレクトリの`module.nix`が定義する`cdn-ncaq-net-sync.service`から呼ばれる。
#
# ```console
# cdn-ncaq-net-sync <ステージングのpublic> <書き終えた印のファイル> <配信ディレクトリ>
# ```
#
# `public`がシンボリックリンクだったら写さずに失敗させます。
# 同期は隔離された場所で動くので、
# リンクの先にあるのはホストのファイルではなく空のディレクトリだったりします。
# そのまま写すと`--delete`で配信ディレクトリが空になるので、写す前に止めます。
#
# 同期の途中で次のジョブが印を更新しても、
# path unitからの起動は今動いている起動にまとめられて、もう一度は走りません。
# 写し始める前の印の時刻を覚えておいて、
# 写し終えた時に更新されていたら写し直します。
#
# `--archive`はリンクや所有者を持ち込むので使わず、必要なものだけを指定します。
# 比べるのは既定のサイズとmtimeで、中身は読みません。
# checkoutのたびにmtimeは変わりますが、
# cdn.ncaq.netのワークフローは`--checksum`付きで`--times`無しのrsyncでステージングへ書くので、
# 中身が変わらないファイルはステージングでmtimeが保たれます。
#
# rsyncを呼んで時刻を比べるだけなので、シェルスクリプトにしています。
{
  coreutils,
  rsync,
  localLib,
  testers,
  writeShellApplication,
}:
writeShellApplication {
  name = "cdn-ncaq-net-sync";
  runtimeInputs = [
    coreutils
    rsync
  ];
  text = ''
    deploy_public=$1
    deploy_stamp=$2
    cdn_root=$3
    seen=$(mktemp)
    while true; do
      touch --reference="$deploy_stamp" "$seen"
      if [[ -L $deploy_public || ! -d $deploy_public ]]; then
        echo "$deploy_public is not a real directory" >&2
        exit 1
      fi
      rsync \
        --recursive \
        --times \
        --perms \
        --chmod=D755,F644 \
        --delete \
        --delete-after \
        --delay-updates \
        --no-links \
        --no-devices \
        --no-specials \
        -- "$deploy_public/" "$cdn_root/"
      if [[ ! $deploy_stamp -nt $seen ]]; then
        break
      fi
      echo "$deploy_stamp was updated during sync, syncing again"
    done
  '';
  # リンクを捨てることと、ユニットの隔離は、実際のユニットを動かさないと確かめられない。
  passthru.tests.nixos = import ./nixos-test.nix { inherit localLib testers; };
}
