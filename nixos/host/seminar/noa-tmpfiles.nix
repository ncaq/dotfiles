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
  options,
  pkgs,
  utils,
  ...
}:
let
  noa = "/mnt/noa";
  noaMount = "${utils.escapeSystemdPath noa}.mount";

  # 全体のtmpfilesの元のコマンドライン。
  # 上書きはこれに`--exclude-prefix`を足して作る。
  # 元の定義とずれていないことを下のassertionと`system.checks`で確かめている。
  # 更新で変わって検査に落ちたら、
  # ここを新しいコマンドラインに合わせる。
  upstreamSetupExecStart = "systemd-tmpfiles --create --remove --boot --exclude-prefix=/dev";
  upstreamResetupExecStart = "systemd-tmpfiles --create --remove --exclude-prefix=/dev";
  # systemd本体のユニットファイル。
  upstreamSetupUnit = "${config.systemd.package}/example/systemd/system/systemd-tmpfiles-setup.service";
  # nixpkgsのモジュールが定義している`systemd-tmpfiles-resetup`の`ExecStart`。
  # ここで`mkForce`した定義も混ざるが、
  # 文字列ではないので一致しない。
  resetupExecStartDefinitions = lib.concatMap (
    definition:
    lib.optional (
      definition ? systemd-tmpfiles-resetup.serviceConfig.ExecStart
    ) definition.systemd-tmpfiles-resetup.serviceConfig.ExecStart
  ) options.systemd.services.definitions;

  isUnderNoa = path: path == noa || lib.hasPrefix "${noa}/" path;
  # `RequiresMountsFor`は文字列1つに空白区切りで複数のパスを書くこともできるので、
  # 分けてから判定する。
  requiresNoa =
    unitDef:
    lib.any isUnderNoa (
      lib.concatMap (lib.splitString " ") (lib.toList (unitDef.unitConfig.RequiresMountsFor or [ ]))
    );
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
  assertions = [
    {
      # 抽出が壊れても`before`が欠けるだけで気付けないので、
      # 1つも拾えていない時は評価を止める。
      assertion = servicesRequiringNoa != [ ];
      message = "noa-tmpfiles: ${noa}の配下を必須にしているサービスが1つも見つかりません。";
    }
    {
      assertion = lib.elem upstreamResetupExecStart resetupExecStartDefinitions;
      message = "noa-tmpfiles: nixpkgsのsystemd-tmpfiles-resetupのExecStartが想定と違います。upstreamResetupExecStartを合わせてください。";
    }
  ];

  # systemd本体のユニットファイルは評価の時には読めないので、
  # システムのビルドの時に確かめる。
  system.checks = [
    (pkgs.runCommand "check-systemd-tmpfiles-setup-exec-start" { } ''
      if ! grep --fixed-strings --line-regexp -- ${lib.escapeShellArg "ExecStart=${upstreamSetupExecStart}"} ${upstreamSetupUnit}; then
        echo "noa-tmpfiles: systemd-tmpfiles-setup.serviceのExecStartが想定と違います。upstreamSetupExecStartを合わせてください。" >&2
        grep ExecStart ${upstreamSetupUnit} >&2
        exit 1
      fi
      touch $out
    '')
  ];

  systemd.services = {
    noa-tmpfiles = {
      description = "Create files and directories under ${noa}";
      # マウントユニットから起動されるようにすると、
      # 起動時のマウントでも、
      # ディスクが欠けた後に手で`mount`した時でも実行される。
      wantedBy = [ noaMount ];
      # アンマウントされたら止まって、
      # 次のマウントでもう一度実行されるようにする。
      bindsTo = [ noaMount ];
      after = [
        noaMount
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
    # 上書きの書き方が2つで違うのは、元の定義の場所が違うから。
    #
    # `systemd-tmpfiles-setup`はsystemd本体のユニットファイルで定義されている。
    # ここでの設定はドロップインになるので、
    # 空文字列で元の`ExecStart`を消してから足す。
    systemd-tmpfiles-setup.serviceConfig.ExecStart = [
      ""
      "${upstreamSetupExecStart} --exclude-prefix=${noa}"
    ];
    # `systemd-tmpfiles-resetup`はnixpkgsのモジュールが定義している。
    # 同じオプションへの定義になるので、
    # `mkForce`で置き換える。
    systemd-tmpfiles-resetup.serviceConfig.ExecStart = lib.mkForce "${upstreamResetupExecStart} --exclude-prefix=${noa}";
  };
}
