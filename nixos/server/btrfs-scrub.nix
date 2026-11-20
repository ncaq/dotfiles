# btrfsは読んだ時にしかチェックサムを照合しないので、
# 滅多に読まないデータの破損に気付けるように定期的に全体を読みます。
# RAID1やDUPのように別のコピーがあれば、その場で修復もされます。
#
# クライアントマシンでは使っている最中に突然重い読み出しが始まるのを避けたいので、
# 常時稼働しているサーバだけで有効にします。
# 対象のファイルシステムと間隔は既定値に任せます。
# 既定では全てのbtrfsをデバイスごとに1回ずつ、月1回scrubします。
{
  lib,
  config,
  utils,
  ...
}:
{
  services.btrfs.autoScrub.enable = true;
  # scrubは大きなファイルシステムだと何時間もかかります。
  # 動いている最中に設定を適用してユニットが変更扱いになると、
  # 途中で止められて最初からやり直しになります。
  # タイマーで起動するので、触らなくても次の回は新しい定義で動きます。
  # ユニット名は上流モジュールの付け方に合わせています。
  systemd.services = lib.listToAttrs (
    map (
      fs:
      lib.nameValuePair "btrfs-scrub-${utils.escapeSystemdPath fs}" {
        restartIfChanged = false;
      }
    ) config.services.btrfs.autoScrub.fileSystems
  );
}
