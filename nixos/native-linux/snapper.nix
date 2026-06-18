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

        # 空き容量がこの割合を下回ると、timeline cleanupが世代数の制限とは別に、
        # 古いスナップショットから追加で削除して空き容量を確保する。
        # 過去にスナップショットがシステムディスクを圧迫したので明示的に引き上げる。
        # FREE_LIMITはstatvfsベースで動作しquota(qgroup)を必要としない。
        # 世代数自体は絞らない。容量に余裕がある限り履歴は多く残して構わない方針。
        FREE_LIMIT = "0.4";
      };
    };
  };

  # 実際の重いbtrfs操作(subvolume削除など)はD-Bus越しにsnapperdが行うため、
  # トリガとなるtimeline/cleanupだけでなくsnapperd本体にも適用する。
  systemd.services = {
    snapper-cleanup.serviceConfig = lowPriority;
    snapper-timeline.serviceConfig = lowPriority;
    snapperd.serviceConfig = lowPriority;
  };
}
