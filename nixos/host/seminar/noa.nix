# `/mnt/noa`のマウントポイントの権限を管理する。
#
# `/mnt/noa`という場所には2つのディレクトリが重なっている。
#
# - noaのbtrfsのトップレベル。マウントされている時に見える
# - ルートのSSDの上のディレクトリ。マウントされていない時に見える
#
# トップレベルはroot所有の0755にする。
# 所有者と権限は`disk.nix`のマウントオプションの`X-mount.owner`などで設定する。
# ブート時のtmpfilesはマウントより前に動いてSSDの側に当たるので、
# tmpfilesのルールでは設定できない。
#
# SSDの側は誰も読み書きできないようにする。
# `/mnt/noa`は`nofail`なので、
# ディスクが欠けてマウントに失敗してもブートは進む。
# その時に何かが書き込むとSSDの側にデータが溜まって、
# 後でマウントした時に下に隠れてしまう。
# 使う側のユニットには`RequiresMountsFor`を付けているが、
# 付け忘れても書き込めないようにしておく。
{
  config,
  hardening,
  lib,
  pkgs,
  ...
}:
let
  # ブートテストのVMのようにマウントが無い構成では、
  # `/mnt/noa`を通常のディレクトリとして使う。
  hasNoaMount = config.fileSystems ? "/mnt/noa";
in
{
  systemd = {
    # マウントが無い構成でのトップレベルの代わり。
    # tmpfilesは非root所有のディレクトリから別の所有者のディレクトリへ降りるのを、
    # "unsafe path transition"として拒否する。
    # 配下の各ディレクトリはそれぞれ個別の所有者を持つので、
    # 親はroot所有にする。
    tmpfiles.rules = lib.mkIf (!hasNoaMount) [
      "d /mnt/noa 0755 root root -"
    ];

    # SSDの側のディレクトリを0000にしてimmutable属性を付ける。
    # rootは権限を無視して書き込めるので、
    # 権限だけでなく属性も要る。
    # どちらもその上へのマウントは妨げない。
    services.noa-mountpoint-immutable = lib.mkIf hasNoaMount {
      description = "Make the mountpoint directory of /mnt/noa inaccessible and immutable";
      wantedBy = [ "local-fs.target" ];
      before = [
        # マウントされた後に動くとトップレベルを書き換えてしまう。
        "mnt-noa.mount"
        "shutdown.target"
      ];
      after = [ "systemd-remount-fs.service" ];
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathIsMountPoint = "!/mnt/noa";
      };
      serviceConfig = hardening.isolated // {
        Type = "oneshot";
        CapabilityBoundingSet = [
          # 0000のディレクトリはrootでもcapabilityが無いと開けない。
          # `chattr`は属性を付ける相手を開く。
          "CAP_DAC_READ_SEARCH"
          "CAP_LINUX_IMMUTABLE"
        ];
        ReadWritePaths = [ "/mnt" ];
        ExecStart = [
          "${lib.getExe' pkgs.coreutils "mkdir"} --parents --mode=0000 /mnt/noa"
          # `--mode`は新しく作った時にしか効かないので、
          # 先に作られていた場合に備えて権限を揃える。
          # immutable属性が付いていると同じ権限への`chmod`も失敗するので、
          # 権限が違う時にだけ実行する。
          # 属性が付いているのに権限が違う時は、
          # 属性を外さずに失敗させて人が確かめる。
          "${lib.getExe pkgs.findutils} /mnt/noa -maxdepth 0 ! -perm 0000 -exec ${lib.getExe' pkgs.coreutils "chmod"} 0000 {} +"
          "${lib.getExe' pkgs.e2fsprogs "chattr"} +i /mnt/noa"
        ];
      };
    };
  };
}
