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
  hardening,
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
        # scrubはカーネルへioctlで依頼して、進捗を`/var/lib/btrfs`のUNIXソケットで受けるだけです。
        # 上流のモジュールは優先度を下げるだけなので、ハードニングを足します。
        #
        # `ProtectSystem`は設定できません。
        # scrubは修復のために対象を書き込み可能で開くので、
        # 対象のマウントが読み取り専用に見えると`Read-only file system`で失敗します。
        # 対象には`/`も含まれるので、`ReadWritePaths`で開けると何も守れません。
        # `ProtectKernelTunables`も設定できません。
        # 速度の上限を`/sys/fs/btrfs`へ書き込むためです。
        serviceConfig =
          removeAttrs hardening.unixSocket [
            "ProtectKernelTunables"
            "ProtectSystem"
          ]
          // {
            # scrubのioctlに必要です。
            CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
          };
      }
    ) config.services.btrfs.autoScrub.fileSystems
  );
}
