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
  本体のあらゆる終了コードとシグナルを挙げて再試行から外します。

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
  # 負荷を検査する回数の上限。最初の1回を含みます。
  # 検査する時点は、この値と`retryServiceConfig`の待ち時間の指定で決まります。
  # 変える時は、冒頭の「負荷と再試行」に書いた時点の説明も合わせます。
  maxAttempts = 5;
  # 再試行を打ち切るかを確かめます。引数はユニットの名前です。
  # `ExecCondition`として動かすので、1で終わるとサービスは失敗ではなく見送りになります。
  # 文字列を取って整数を比べるだけなので、シェルスクリプトにします。
  retryLimit = pkgs.writeShellApplication {
    name = "nix-store-maintenance-retry-limit";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      # 起動し直した回数は、済んだ検査の回数と同じです。
      restarts=$(systemctl show --property=NRestarts --value "$1")
      if [ "$restarts" -ge ${toString maxAttempts} ]; then
        echo "確かめ直しても負荷が下がらないので、今回は見送ります"
        exit 1
      fi
    '';
  };
  # ストアの手入れを始めてよいかを確かめます。
  # `ExecStartPre`として動かすので、0以外で終わるとサービスは失敗になり、
  # `Restart=on-failure`が時間を置いて起動し直します。
  # ホストごとの前処理より先に動かすので、
  # 負荷が高い時はホストごとの前処理は動きません。
  # `ExecStopPost`は前処理が失敗した時にも動くので、
  # ホストごとの後処理は前処理が動いていなくても害の無いものにします。
  #
  # 条件をsystemdの`ConditionCPUPressure`で書かないのは、
  # 圧力が示すのはCPUの取り合いであって、使われている量ではないからです。
  # スレッドの数ちょうどまで使うジョブは取り合いを起こさないので、
  # 動いている最中でも圧力は低いままです。
  #
  # 小数の比較があるのでシェルスクリプトにはしません。
  # ロードアベレージは`loadavg`がlibcの`getloadavg(3)`から小数で取るので、
  # `/proc/loadavg`を自分で読み解く処理もありません。
  condition =
    pkgs.writers.writeHaskellBin "nix-store-maintenance-condition"
      {
        libraries = [ pkgs.haskellPackages.loadavg ];
        # 警告は`pkgs`のcabalプロジェクトと同じものを有効にします。
        # cabalを通さないので、言語の版と最適化もここで指定します。
        ghcArgs = [
          "-XGHC2024"
          "-O2"
          "-Wall"
          "-Wcompat"
          "-Widentities"
          "-Wincomplete-record-updates"
          "-Wincomplete-uni-patterns"
          "-Wpartial-fields"
          "-Wredundant-constraints"
          # ビルドの出力は誰も読まないので、警告はビルドの失敗にして気付けるようにします。
          "-Werror"
        ];
        # スレッドは使いませんが、スレッド対応のランタイムを外してはいけません。
        # 外すと`getNumProcessors`が常に1を返して、上限が0.5になります。
        threadedRuntime = true;
      }
      ''
        import GHC.Conc (getNumProcessors)
        import GHC.IO.Encoding (setLocaleEncoding, utf8)
        import Numeric (showFFloat)
        import System.Exit (ExitCode (ExitFailure), exitWith)
        import System.IO (hPutStrLn, stderr)
        import System.Posix.LoadAvg (LoadAvg (sample_1, sample_5), getLoadAvgSafe)

        main :: IO ()
        main = do
          -- systemdから起動された時のロケールに関わらず、日本語のメッセージを出せるようにします。
          setLocaleEncoding utf8
          threads <- getNumProcessors
          mLoadAvg <- getLoadAvgSafe
          case mLoadAvg of
            Nothing -> do
              hPutStrLn stderr "ロードアベレージを取得できませんでした"
              exitWith (ExitFailure 255)
            Just loadAvg
              -- 直近1分と直近5分のどちらかがスレッドの数の半分を超えていたら始めません。
              -- 直近1分は、始まったばかりのジョブに気付くために見ます。
              -- 直近5分は、ジョブの合間に負荷が一瞬だけ下がった時に始めてしまわないために見ます。
              | load1 > limit || load5 > limit -> do
                  putStrLn $
                    "負荷が高いので始めません: ロードアベレージが直近1分で"
                      <> showFFloat (Just 2) load1 ""
                      <> "、直近5分で"
                      <> showFFloat (Just 2) load5 ""
                      <> "、上限は"
                      <> showFFloat (Just 2) limit ""
                  exitWith (ExitFailure 1)
              | otherwise -> pure ()
              where
                load1 = sample_1 loadAvg
                load5 = sample_5 loadAvg
                limit = fromIntegral threads / 2 :: Double
      '';
in
{
  options.local.nixStoreMaintenance.retryServiceConfig = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = {
      # 先頭の`+`はサービスのサンドボックスの外で動かす指定です。
      # サンドボックスを持つサービスからも`systemctl`でsystemdに問い合わせられるようにします。
      # `%n`はユニットの名前に展開されます。
      ExecCondition = "+${lib.getExe retryLimit} %n";
      ExecStartPre = [ (lib.getExe condition) ];
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
