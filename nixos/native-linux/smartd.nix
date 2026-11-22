# ディスクのSMARTの値を見張って、
# 寿命や予備領域の残りが交換を考えるべき状態になったことに気付けるようにします。
# 既定の`-a`は値を読むだけで、
# セルフテストのような重い処理は予約しないので、
# クライアントマシンでも有効にします。
# WSLでは物理ディスクが見えないので対象外です。
{ pkgs, hardening, ... }:
{
  services.smartd.enable = true;
  # `smartctl`
  environment.systemPackages = [ pkgs.smartmontools ];

  # smartdはrootのままディスクへ生のコマンドを送ります。
  # nixpkgsのモジュールは何も絞っていないので、
  # ディスクを読むことと、問題を端末へ知らせることの他は閉じます。
  # 状態のファイルは保存していないので、書き込む先はありません。
  #
  # メールでの通知は使っていないのでネットワークも閉じています。
  # 有効にする時はここを見直す必要があります。
  systemd.services.smartd.serviceConfig =
    removeAttrs hardening.unixSocket [
      # ディスクのデバイスファイルそのものが要るので、下の`DeviceAllow`で個別に開けます。
      "PrivateDevices"
      # X11での通知が`/tmp/.X11-unix`のソケットへ繋ぎます。
      "PrivateTmp"
    ]
    // {
      CapabilityBoundingSet = [
        # SATAのディスクへSG_IOでATAコマンドを送る。
        "CAP_SYS_RAWIO"
        # NVMeのadminコマンドを送る。
        "CAP_SYS_ADMIN"
      ];
      # 開けるデバイスを、見張るディスクと通知先の端末だけにします。
      # ハードウェアRAIDのコントローラ越しのディスクは使っていないので入れていません。
      DevicePolicy = "closed";
      DeviceAllow = [
        # SATAとUSBのディスク。
        "block-sd r"
        # NVMeはコントローラのキャラクタデバイスを開く。
        "char-nvme r"
        # `wall`での通知は、ログインしている端末へ書き込む。
        "char-pts w"
        "char-tty w"
      ];
      # 端末はユーザの所有で、グループの`tty`にだけ書き込みを許している。
      # `wall`は普通はsetgidで`tty`になるが、Nix storeのものには付いていない。
      # rootでも他人のファイルへ書くには`CAP_DAC_OVERRIDE`が要るので、
      # それを渡す代わりにグループへ入れる。
      SupplementaryGroups = [ "tty" ];
    };
}
