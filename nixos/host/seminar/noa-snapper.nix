{
  services.snapper = {
    configs = {
      noa = {
        SUBVOLUME = "/mnt/noa";

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;

        # 空き容量が逼迫した時に世代数の下限まで追加で削除する。
        # 範囲指定が必要な理由やSPACE_LIMITを使わない理由は、
        # rootの設定がある`nixos/native-linux/snapper.nix`に書いている。
        TIMELINE_LIMIT_HOURLY = "2-10";
        TIMELINE_LIMIT_DAILY = "2-10";
        TIMELINE_LIMIT_MONTHLY = "2-10";
        TIMELINE_LIMIT_YEARLY = "2-10";
        FREE_LIMIT = "0.2";
      };
    };
  };
}
