# ストアの手入れ(GCと最適化)を始めてよいかを確かめるコマンド。
#
# 同じディレクトリの`module.nix`が定義するユニットから呼ばれる。
# いつ何のために呼ぶかは`module.nix`の冒頭に書いてある。
#
# - `nix-store-maintenance-retry-limit`: 再試行を打ち切るかを確かめる
# - `nix-store-maintenance-condition`: 負荷が低いかを確かめる
{
  lib,
  haskellPackages,
  symlinkJoin,
  systemd,
  testers,
  writeShellApplication,
  writers,
}:
let
  # 負荷を検査する回数の上限。最初の1回を含みます。
  # 検査する時点は、この値と`module.nix`の`retryServiceConfig`の待ち時間の指定で決まります。
  # 変える時は、`module.nix`の冒頭の「負荷と再試行」に書いた時点の説明も合わせます。
  maxAttempts = 5;
  # 再試行を打ち切るかを確かめます。引数はユニットの名前です。
  # `ExecCondition`として動かすので、1で終わるとサービスは失敗ではなく見送りになります。
  # 文字列を取って整数を比べるだけなので、シェルスクリプトにします。
  retryLimit = writeShellApplication {
    name = "nix-store-maintenance-retry-limit";
    runtimeInputs = [ systemd ];
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
    writers.writeHaskellBin "nix-store-maintenance-condition"
      {
        libraries = [ haskellPackages.loadavg ];
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
symlinkJoin {
  name = "nix-store-maintenance";
  paths = [
    condition
    retryLimit
  ];
  passthru = {
    # テストが打ち切りの回数を確かめるのに使います。
    inherit maxAttempts;
    # 再試行と打ち切りはsystemdの振る舞いとの組み合わせなので、コンテナの中で実際のユニットを動かす。
    tests.nixos = import ./nixos-test.nix { inherit lib testers maxAttempts; };
  };
}
