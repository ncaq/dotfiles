{ pkgs, ... }:
let
  # snapperのスナップショット作成・クリーンアップは緊急性がないので、
  # 他のプロセスを妨害しないようにCPUとI/Oの優先度を下げる。
  lowPriority = {
    # CPUはniceとidleクラスで確実に後回しにできる。スケジューラに依存しない。
    Nice = 19;
    CPUSchedulingPolicy = "idle";
    # `IOSchedulingClass = idle`はmq-deadlineやBFQで有効。
    # カーネル5.18以降のmq-deadlineはI/O優先度対応なので効くが、
    # idleリクエストの餓死防止で緩く割り込む。
    # NVMeのnoneスケジューラでは効かない。
    IOSchedulingClass = "idle";
    # IOWeight(cgroupのio.weight)による比例配分はBFQでのみ効く。
    # mq-deadlineやnoneでは効かないが無害なので、
    # 将来BFQに切り替えた場合に備えて指定しておく。
    IOWeight = 10;
  };
in
{
  services.snapper = {
    configs = {
      root = {
        SUBVOLUME = "/";

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;

        # SPACE_LIMITやFREE_LIMITによる容量ベースのcleanupは、
        # timeline cleanupのリミットがmin-maxの範囲指定の時のみ機能する。
        # snapperはまず各カテゴリのmax値までcleanupし(1パス目)、
        # それでもSPACE_LIMIT/FREE_LIMITを満たせない時だけ、
        # min値まで追加で削除する(2パス目)。
        # maxは従来のデフォルト値、minは容量が逼迫した時に残す最低世代数。
        TIMELINE_LIMIT_HOURLY = "2-10";
        TIMELINE_LIMIT_DAILY = "2-10";
        TIMELINE_LIMIT_MONTHLY = "2-10";
        TIMELINE_LIMIT_YEARLY = "2-10";

        # スナップショットが使ってよい容量をファイルシステム全体の1割までに制限する。
        # SPACE_LIMITはqgroup(btrfs quota)のexclusive使用量 / FS全体サイズで評価される、
        # cleanup時のソフトリミット。
        # quotaの有効化とqgroupの用意はsnapper-setup-quotaサービスで行い、
        # 参照するqgroupは下のQGROUPで宣言的に指定する。
        SPACE_LIMIT = "0.1";

        # snapperが使用量計測に使うレベル1のqgroup。
        # NixOSでは`/etc/snapper/configs/root`がread-onlyのため、
        # configにQGROUPを書き込む`snapper setup-quota`は使えない。
        # 代わりにこの値を宣言的に与え、qgroup自体はサービスで作成する。
        QGROUP = "1/0";

        # 空き容量がこの割合を下回ると、timeline cleanupが世代数の制限とは別に、
        # 古いスナップショットから追加で削除して空き容量を確保する。
        # 明示的に記述しておく。
        # FREE_LIMITはstatvfsベースで動作しquota(qgroup)を必要としない。
        # SPACE_LIMITが信用できなかった場合の安全網として併用する。
        FREE_LIMIT = "0.2";
      };
    };
  };

  systemd.services = {
    # snapperのSPACE_LIMITはbtrfsのquota(qgroup)を前提とするが、
    # NixOSにはquotaを宣言的に有効化するオプションがない。
    # そのためquotaの有効化とqgroupの作成だけをoneshotサービスで命令的に行う。
    # quotaモードは、従来のfull quotaだとスナップショットが多い環境で、
    # 書き込み性能の低下やcleanup時の高負荷を招くため、
    # simple quota(squota)を使う。
    # squotaは有効化後の書き込みのみ計測するので既存分は0から始まるが、
    # 新規スナップショットの差分から徐々に正確になる。
    snapper-setup-quota = {
      description = "Enable btrfs simple quota and qgroup for snapper SPACE_LIMIT";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [
        "snapper-cleanup.service"
        "snapper-timeline.service"
        "snapperd.service"
      ];
      unitConfig.ConditionPathIsMountPoint = "/";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = with pkgs; [
        btrfs-progs
        gnugrep
      ];
      script = ''
        # simple quotaを有効化する。既に有効でも無害に終了する。
        btrfs quota enable --simple /
        # snapperが参照するレベル1のqgroupを用意する。既存ならスキップする。
        if ! btrfs qgroup show / | grep -qE '^1/0[[:space:]]'; then
          btrfs qgroup create 1/0 /
        fi
      '';
    };

    # 実際の重いbtrfs操作(subvolume削除など)はD-Bus越しにsnapperdが行うため、
    # トリガとなるtimeline/cleanupだけでなくsnapperd本体にも適用する。
    snapper-cleanup.serviceConfig = lowPriority;
    snapper-timeline.serviceConfig = lowPriority;
    snapperd.serviceConfig = lowPriority;
  };
}
