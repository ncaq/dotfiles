/**
  ストアのGCと最適化を、毎日決まった時刻に続けて動かします。

  どちらも稼働に必須ではないので、
  ホストを使っている人やジョブの邪魔になりそうな時は始めません。
  しばらく待って確かめ直し、それでも駄目なら次の日へ回します。
  ホストの空きが本当に足りなくなった時は、
  `nix-daemon.nix`の`min-free`がビルドの途中でGCします。
  ホストが完全に立ち往生しないための備えで、VMの中の空きには関わりません。

  # 順序

  GCが消したパスを最適化が読むのは無駄なので、
  GCの後に最適化を動かします。
  同じ時刻のタイマーを2つ並べても、
  systemdはどちらを先に起動するかを決めてくれません。
  タイマーはGCだけに持たせて、
  GCが終わった時に最適化を起動させます。
  GCを動かしてよいと判断した後なので、
  最適化は負荷を確かめ直さずに動きます。
  GCが見送られた時と失敗した時は、最適化も動きません。

  起動させるのに`OnSuccess`を使わないのは、
  `ExecCondition`で見送られた時にも`OnSuccess`が発火するからです。
  `ExecStartPost`はGCの本体が成功した時にだけ動きます。

  # 負荷と再試行

  負荷が高い時は、時間を置いて確かめ直します。
  負荷を細かい条件で見分けようとするより、
  何度か確かめ直すほうが、
  直前の処理が上げた一時的な負荷にも強くなります。

  待つのも繰り返すのもsystemdに任せます。
  負荷の検査は`ExecStartPre`に置いて、負荷が高い時は失敗させます。
  `Restart=on-failure`が起動し直して、
  `RestartSteps`が待ち時間を5分から40分まで倍々に伸ばします。
  検査は最初の1回と合わせて、0分、5分、15分、35分、75分の時点の5回です。

  回数は`ExecCondition`で打ち切ります。
  `Restart`には回数の上限が無く、
  `StartLimitBurst`で止めるとユニットがfailedで残ります。
  `ExecCondition`で止めると失敗ではなく見送りになり、
  見送りは`Restart`の対象にもなりません。

  再試行するのは負荷の検査で止まった時だけです。
  本体の失敗は時間を置いても直らないことが多く、
  繰り返すと負荷だけがかかるので、本体が失敗した時とタイムアウトした時は再試行しません。
  `RestartPreventExitStatus`が見るのは本体の終了の仕方だけで、
  `ExecStartPre`の失敗には効かないので、
  本体のあらゆる終了コードと、タイムアウトの時に送られるシグナルを挙げて再試行から外します。
  本体がそれ以外のシグナルで異常終了した時は、再試行されます。

  `ExecStartPost`の失敗も再試行されます。
  本体は成功で終わっているので、再試行から外す対象に当たらないからです。
  その時は本体がもう一度動くので、
  `ExecStartPost`には失敗しうる重い処理を置かないようにします。

  # 逃した回

  電源が落ちていて時刻を逃した回は、
  次の起動の時に動きます。
  朝より後に起動するラップトップでも毎日動かすためです。
  ただし起動の直後に動くとログインや作業の始めと重なるので、
  起動からしばらくは待ちます。

  systemdのタイマーには、逃した回を遅らせて動かす指定がありません。
  逃した回が動くのはタイマーが有効になった時なので、
  タイマーを有効にするのを遅らせます。
  GCのタイマーを`timers.target`から外して、
  起動からの時間で動く別のタイマーに有効にさせます。
  有効になる前に過ぎた時刻も逃した回として扱われるので、
  起動の直後に時刻が来た日も、有効になった時に動きます。

  # 置き場所

  負荷の検査と打ち切りのコマンド(`package.nix`)と対になっているので、パッケージの隣に置いています。
  全ホストが`nixos/core/nix-store-maintenance.nix`から読み込みます。
  テスト(`nixos-test.nix`)もこのモジュールだけを読むので、ホストの構成に依存しません。
*/
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # 稼働中のsystemdと同じパッケージの`systemctl`。
  systemctl = lib.getExe' config.systemd.package "systemctl";
  # 負荷の検査と再試行の打ち切りのコマンド。中身は隣の`package.nix`にあります。
  # `systemctl`が稼働中のsystemdと同じパッケージになるようにします。
  package = pkgs.nix-store-maintenance.override { systemd = config.systemd.package; };
  retryLimit = lib.getExe' package "nix-store-maintenance-retry-limit";
  condition = lib.getExe' package "nix-store-maintenance-condition";
in
{
  options.local.nixStoreMaintenance.retryServiceConfig = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = {
      # 先頭の`+`はサービスのサンドボックスの外で動かす指定です。
      # サンドボックスを持つサービスからも`systemctl`でsystemdに問い合わせられるようにします。
      # `%n`はユニットの名前に展開されます。
      ExecCondition = "+${retryLimit} %n";
      ExecStartPre = [ condition ];
      Restart = "on-failure";
      RestartSec = "5min";
      RestartSteps = 3;
      RestartMaxDelaySec = "40min";
      # 本体が失敗した時は再試行しません。
      # 終了コードは範囲で書けないので、全て並べます。
      # シグナルは、タイムアウトの時にsystemdが送るものです。
      # リストにするとユニットに値の数だけ行が並ぶので、1行の文字列にします。
      RestartPreventExitStatus = lib.concatStringsSep " " (
        map toString (lib.range 1 255)
        ++ [
          "SIGTERM"
          "SIGKILL"
        ]
      );
    };
    description = ''
      負荷が高い時は始めずに、時間を置いて確かめ直すための`serviceConfig`。
      GCの前に別の処理を挟むホストが、その処理にも同じ振る舞いをさせるのに使う。
    '';
  };

  config.nix = {
    gc = {
      automatic = true;
      # ホストのタイムゾーンの設定に関わらず、日本時間の朝に動かします。
      dates = "*-*-* 08:00:00 Asia/Tokyo";
    };
    # タイマーを持たせないために偽にします。
    # サービスは偽でも定義されて、GCが連れて起動します。
    optimise.automatic = false;
  };

  config.systemd = {
    services = {
      nix-gc = {
        # 起動を頼んだ最適化は、GCの後処理まで終わってから動き出します。
        before = [ "nix-optimise.service" ];
        serviceConfig = config.local.nixStoreMaintenance.retryServiceConfig // {
          # 負荷の検査は、ホストごとの前処理より先に動かします。
          # 負荷が高い時は検査が失敗して、ホストごとの前処理は動きません。
          # `ExecStopPost`は前処理が失敗した時にも動くので、
          # ホストごとの後処理は前処理が動いていなくても害の無いものにします。
          ExecStartPre = lib.mkBefore config.local.nixStoreMaintenance.retryServiceConfig.ExecStartPre;
          # 最適化の終わりは待ちません。
          # 待つとGCのユニットが最適化の間も起動の途中のままになります。
          ExecStartPost = "${systemctl} start --no-block nix-optimise.service";
        };
      };
    };
    timers = {
      # 起動の時には有効にせず、下のタイマーに任せます。
      nix-gc.wantedBy = lib.mkForce [ ];
      nix-gc-after-boot = {
        description = "Enable the Nix Garbage Collector timer once the boot has settled";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "15min";
          Unit = "nix-gc.timer";
        };
      };
    };
  };
}
