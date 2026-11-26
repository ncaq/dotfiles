# `/mnt/noa`の配下を対象にしたsystemd-tmpfilesのルールを、マウントされた後に適用する。
#
# `systemd-tmpfiles-setup.service`は`local-fs.target`までしか待たない。
# `/mnt/noa`は`nofail`なので`local-fs.target`はマウントを待たず、
# ブート時のtmpfilesはマウントより前に動く。
# その時点の`/mnt/noa`は`noa.nix`が書き込めなくしたディレクトリなので、
# 配下のルールは全て失敗する。
#
# systemdにもNixOSにも、マウントに連動してtmpfilesを適用する仕組みは無い。
# そこで全体のtmpfilesからは`/mnt/noa`を外して、
# マウントに連動する専用のユニットで`/mnt/noa`の配下だけを適用する。
# ルールは今まで通り`systemd.tmpfiles.rules`などに書けばよい。
{
  config,
  hardening,
  lib,
  ...
}:
let
  noa = "/mnt/noa";

  isUnderNoa = path: path == noa || lib.hasPrefix "${noa}/" path;
  requiresNoa =
    unitDef: lib.any isUnderNoa (lib.toList (unitDef.unitConfig.RequiresMountsFor or [ ]));
  # `RequiresMountsFor`で`/mnt/noa`の配下を必須にしているユニットの名前。
  # 自分自身の`unitConfig`は`before`から作られるので、
  # 見ると無限再帰になる。
  servicesRequiringNoa = map (name: "${name}.service") (
    lib.attrNames (
      lib.filterAttrs (_: requiresNoa) (removeAttrs config.systemd.services [ "noa-tmpfiles" ])
    )
  );
in
lib.mkIf (config.fileSystems ? ${noa}) {
  systemd.services = {
    noa-tmpfiles = {
      description = "Create files and directories under ${noa}";
      # マウントユニットから起動されるようにすると、
      # 起動時のマウントでも、
      # ディスクが欠けた後に手で`mount`した時でも実行される。
      wantedBy = [ "mnt-noa.mount" ];
      # アンマウントされたら止まって、
      # 次のマウントでもう一度実行されるようにする。
      bindsTo = [ "mnt-noa.mount" ];
      after = [
        "mnt-noa.mount"
        "systemd-sysusers.service"
      ];
      # 空のnoaを作り直した直後でも、
      # 配下を使うユニットがディレクトリの作成より先に起動しないようにする。
      # 使う側はマウントを必須にしていて、
      # マウントがこのユニットを起動するので、
      # 順序付けるだけで待つようになる。
      # `systemd.services`の`unitConfig`以外でマウントを必須にしているユニットは拾えないので、
      # そのユニットの側で`After`を書く。
      before = servicesRequiringNoa;
      # ルールが変わった時にswitchで適用し直す。
      # `systemd-tmpfiles-resetup.service`と同じ方法。
      restartTriggers = [ config.environment.etc."tmpfiles.d".source ];
      serviceConfig = hardening.unixSocket // {
        Type = "oneshot";
        RemainAfterExit = true;
        # `--boot`は起動時に一度だけ実行する全体のtmpfilesのためのものなので付けない。
        ExecStart = "systemd-tmpfiles --create --remove --prefix=${noa}";
        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_FOWNER"
        ];
        ReadWritePaths = [ noa ];
      };
    };

    # 全体のtmpfilesから`/mnt/noa`を外す。
    # 外さないとブートのたびに配下のルールが失敗してログに残る。
    # `ExecStart`はどちらも元のコマンドラインに`--exclude-prefix`を足したもの。
    # systemdやnixpkgsの更新で元のコマンドラインが変わったら合わせる。
    systemd-tmpfiles-setup.serviceConfig.ExecStart = [
      ""
      "systemd-tmpfiles --create --remove --boot --exclude-prefix=/dev --exclude-prefix=${noa}"
    ];
    systemd-tmpfiles-resetup.serviceConfig.ExecStart = lib.mkForce "systemd-tmpfiles --create --remove --exclude-prefix=/dev --exclude-prefix=${noa}";
  };
}
