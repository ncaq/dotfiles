{
  config,
  lib,
  pkgs,
  ...
}:
{
  systemd = {
    # `/mnt/noa`はbtrfsトップレベルを直接マウントしたストレージのルート。
    # ルートファイルシステム(`/`)がroot所有なのと同様に、
    # マウントポイント自体はroot所有とする。
    # 一般ユーザの読み取りと走査は可能なように0755にしておき、
    # 配下の各ディレクトリはそれぞれ個別の所有者と権限を持つ。
    #
    # これによりsystemd-tmpfilesの"unsafe path transition"判定を回避できる。
    # tmpfilesは非root所有のディレクトリから別の所有者のディレクトリへ降りる遷移を、
    # シンボリックリンク攻撃対策として拒否するが、
    # 親がroot所有なら子が別の所有者でも安全と判定する。
    tmpfiles.rules = [
      "d /mnt/noa 0755 root root -"
    ];

    # マウントポイントのディレクトリ自体にimmutable属性を付ける。
    #
    # `/mnt/noa`は`nofail`なので、
    # ディスクが欠けてマウントに失敗してもブートは進む。
    # その時に`/mnt/noa`はルートのSSDの上のただのディレクトリになり、
    # 何かが書き込むとSSDの側にデータが溜まって、
    # 後でマウントした時に下に隠れてしまう。
    # 使う側のユニットには`RequiresMountsFor`を付けているが、
    # 付け忘れても書き込めないように、
    # 隠れる側のディレクトリを書き込めなくしておく。
    # immutable属性が付いていてもその上へのマウントはできて、
    # マウントした後に見えるのはnoaのトップレベルなので影響は無い。
    #
    # ブートテストのVMのように`/mnt/noa`のマウントが無い構成では、
    # 通常のディレクトリとして使うので定義しない。
    services.noa-mountpoint-immutable = lib.mkIf (config.fileSystems ? "/mnt/noa") {
      description = "Make the mountpoint directory of /mnt/noa immutable";
      wantedBy = [ "local-fs.target" ];
      before = [
        # マウントされた後に実行するとnoaのトップレベルに属性を付けてしまうので、
        # マウントより前に順序付ける。
        "mnt-noa.mount"
        "shutdown.target"
      ];
      after = [ "systemd-remount-fs.service" ];
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        DefaultDependencies = false;
        # 順序付けた上で、マウントされていない時にだけ動くようにする。
        ConditionPathIsMountPoint = "!/mnt/noa";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${lib.getExe' pkgs.coreutils "mkdir"} --parents /mnt/noa"
          "${lib.getExe' pkgs.e2fsprogs "chattr"} +i /mnt/noa"
        ];
      };
    };
  };
}
