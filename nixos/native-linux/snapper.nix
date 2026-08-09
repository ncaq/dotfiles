_:
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

        # FREE_LIMITによる容量ベースのcleanupは、
        # timeline cleanupのリミットがmin-maxの範囲指定の時のみ機能する。
        # snapperはまず各カテゴリのmax値までcleanupし(1パス目)、
        # それでもFREE_LIMITを満たせない時だけ、
        # min値まで追加で削除する(2パス目)。
        # maxは従来のデフォルト値、minは容量が逼迫した時に残す最低世代数。
        TIMELINE_LIMIT_HOURLY = "2-10";
        TIMELINE_LIMIT_DAILY = "2-10";
        TIMELINE_LIMIT_MONTHLY = "2-10";
        TIMELINE_LIMIT_YEARLY = "2-10";

        # 空き容量がこの割合を下回ると、timeline cleanupが世代数の制限とは別に、
        # 古いスナップショットから追加で削除して空き容量を確保する。
        # FREE_LIMITはstatvfsベースで動作しquota(qgroup)を必要としない。
        #
        # スナップショットの使用量を直接制限するSPACE_LIMITもあるが、
        # そちらはbtrfsのfull quota(qgroup)を必要とするため使わない。
        # full quotaはextentの参照が増減するたびにbackref walkを行うので、
        # beesによる重複排除でextentの共有度が上がるほど、
        # またスナップショットが増えるほどコストが膨らむ。
        # 実際にbtrfs-transactionとbtrfs-cleanerがカーネル空間のCPUを占有し、
        # トランザクションコミット待ちで無関係なプロセスまで停止していた。
        # 加えてカーネルはsubtree dropが深くなるとqgroupの再計算を放棄して、
        # quotaをinconsistentとしてマークするため、
        # SPACE_LIMITが読む値自体が信用できない状態になっていた。
        #
        # 防ぎたいのはスナップショットで埋まって書き込めなくなる事態であり、
        # それは空き容量で直接判定できるのでFREE_LIMITだけで足りる。
        FREE_LIMIT = "0.2";
      };
    };
  };

  systemd.services = {
    # 実際の重いbtrfs操作(subvolume削除など)はD-Bus越しにsnapperdが行うため、
    # トリガとなるtimeline/cleanupだけでなくsnapperd本体にも適用する。
    snapper-cleanup.serviceConfig = lowPriority;
    snapper-timeline.serviceConfig = lowPriority;
    snapperd.serviceConfig = lowPriority;
  };
}
