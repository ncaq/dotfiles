/**
  ストアのGCと最適化を、毎日決まった時刻に続けて動かします。

  どちらも稼働に必須ではないので、
  ホストを使っている人やジョブの邪魔になりそうな時は動かさずに次の日へ回します。
  空きが本当に足りなくなった時は、
  `nix-daemon.nix`の`min-free`がビルドの途中でGCします。

  # 順序

  GCが消したパスを最適化が読むのは無駄なので、
  GCの後に最適化を動かします。
  同じ時刻のタイマーを2つ並べても、
  systemdはどちらを先に起動するかを決めてくれません。
  タイマーはGCだけに持たせて、
  GCが終わった時に最適化を起動させます。
  GCを動かしてよいと判断した後なので、
  最適化は条件を確かめ直さずに動きます。
  GCが見送られた時と失敗した時は、最適化も動きません。

  起動させるのに`OnSuccess`を使わないのは、
  `ExecCondition`で見送られた時にも`OnSuccess`が発火するからです。
  `ExecStartPost`はGCの本体が成功した時にだけ動きます。

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
  # ストアの手入れを始めてよいかを確かめます。
  # `ExecCondition`として動かすので、
  # 1から254で終わるとサービスは失敗ではなく見送りになり、
  # 255で終わると失敗になります。
  # `ExecStartPre`より前に動くので、
  # 見送る時はホストごとの前処理も動きません。
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
              -- 直近1分と直近5分のどちらかがスレッドの数の半分を超えていたら見送ります。
              -- 直近1分は、始まったばかりのジョブに気付くために見ます。
              -- 直近5分は、ジョブの合間に負荷が一瞬だけ下がった時に始めてしまわないために見ます。
              | load1 > limit || load5 > limit -> do
                  putStrLn $
                    "負荷が高いので見送ります: ロードアベレージが直近1分で"
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
  nix = {
    gc = {
      automatic = true;
      # ホストのタイムゾーンの設定に関わらず、日本時間の朝に動かします。
      dates = "*-*-* 08:00:00 Asia/Tokyo";
    };
    # タイマーを持たせないために偽にします。
    # サービスは偽でも定義されて、GCが連れて起動します。
    optimise.automatic = false;
  };

  systemd = {
    services = {
      nix-gc = {
        # 起動を頼んだ最適化は、GCの後処理まで終わってから動き出します。
        before = [ "nix-optimise.service" ];
        serviceConfig = {
          ExecCondition = lib.getExe condition;
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
