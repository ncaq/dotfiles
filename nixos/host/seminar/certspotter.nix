{
  pkgs,
  lib,
  ...
}:
let
  # certspotterのhookが検知したイベントを1行のJSONとして追記するログ。
  # hookとチェックの両方へここから埋め込み、パスの定義はこの1箇所だけにします。
  eventsLog = "/var/lib/certspotter/events.log";
  # この時間以内のイベントがあればMackerelのチェックをCRITICALにします。
  # アラートが一定期間開いたままになることで見落としを防ぎます。
  alertWindowSeconds = 24 * 60 * 60;

  # hookとチェックはシェルではなくHaskellで書きます。
  # `SUMMARY`や`ISSUER_DN`やSANはCA/CTログ由来の信頼できない値で、
  # シェルで制御文字を潰すだけでは漏れが出やすいためです。
  # aesonに記録と読み取りの両方を任せれば、
  # 改行やタブが入っても列ずれや偽の行は構造的に起きません。
  haskellLibraries = hpkgs: [ hpkgs.aeson ];
  ghcArgs = [
    "-Wall"
    "-Werror"
  ];

  # 環境変数の仕様は`man 8 certspotter-script`を参照。
  # `discovered_cert`以外(`malformed_cert`, `error`)も監視自体の異常なので記録します。
  mkHook =
    { eventsLog }:
    pkgs.writers.writeHaskellBin "certspotter-hook"
      {
        libraries = haskellLibraries;
        inherit ghcArgs;
      }
      ''
        {-# LANGUAGE GHC2024 #-}
        {-# LANGUAGE OverloadedStrings #-}
        module Main (main) where

        import Data.Aeson (Value, eitherDecodeFileStrict', encode, object, withObject, (.!=), (.:?), (.=))
        import Data.Aeson.Types (parseEither)
        import Data.ByteString.Lazy qualified as BL
        import Data.Maybe (fromMaybe)
        import Data.Text (Text)
        import Data.Text qualified as T
        import Data.Time.Clock.POSIX (getPOSIXTime)
        import System.Environment (lookupEnv)
        import System.IO (IOMode (AppendMode), withBinaryFile)

        eventsLog :: FilePath
        eventsLog = "${eventsLog}"

        -- 証明書のJSONから`dns_names`だけを取り出す。
        -- 取り出せない時は空にして、イベント自体の記録は止めない。
        dnsNamesOf :: FilePath -> IO [Text]
        dnsNamesOf path = do
          decoded <- eitherDecodeFileStrict' path :: IO (Either String Value)
          pure $ case decoded >>= parseEither (withObject "cert" (\o -> o .:? "dns_names" .!= [])) of
            Left _ -> []
            Right names -> names

        main :: IO ()
        main = do
          event <- fromMaybe "unknown" <$> lookupEnv "EVENT"
          summary <- fromMaybe "" <$> lookupEnv "SUMMARY"
          issuer <- fromMaybe "" <$> lookupEnv "ISSUER_DN"
          jsonFile <- lookupEnv "JSON_FILENAME"
          dnsNames <- case jsonFile of
            Just path | event == "discovered_cert" -> dnsNamesOf path
            _ -> pure []
          now <- round <$> getPOSIXTime :: IO Integer
          let record =
                object
                  [ "time" .= now
                  , "event" .= T.pack event
                  , "summary" .= T.pack summary
                  , "dns_names" .= dnsNames
                  , "issuer" .= T.pack issuer
                  ]
          withBinaryFile eventsLog AppendMode $ \h -> BL.hPut h (encode record <> "\n")
      '';

  # `checkService`を偽にするとsystemdの状態確認を省きます。
  # ビルドサンドボックス内のテストで使うためです。
  mkCheck =
    {
      eventsLog,
      checkService,
    }:
    pkgs.writers.writeHaskellBin "check-certspotter"
      {
        libraries = haskellLibraries;
        inherit ghcArgs;
      }
      ''
        {-# LANGUAGE GHC2024 #-}
        {-# LANGUAGE OverloadedStrings #-}
        module Main (main) where

        import Control.Monad (unless, when)
        import Data.Aeson (FromJSON (parseJSON), decodeStrict, withObject, (.!=), (.:), (.:?))
        import Data.ByteString.Char8 qualified as BS
        import Data.Char (GeneralCategory (Control, Format, LineSeparator, ParagraphSeparator), generalCategory)
        import Data.Maybe (mapMaybe)
        import Data.Text (Text)
        import Data.Text qualified as T
        import Data.Text.IO qualified as T
        import Data.Time.Clock.POSIX (getPOSIXTime, posixSecondsToUTCTime)
        import Data.Time.Format (defaultTimeLocale, formatTime)
        import System.Directory (doesFileExist)
        import System.Exit (ExitCode (ExitFailure, ExitSuccess), exitWith)
        import System.IO (hSetEncoding, stdout, utf8)
        import System.Process (readProcessWithExitCode)

        eventsLog :: FilePath
        eventsLog = "${eventsLog}"

        alertWindowSeconds :: Integer
        alertWindowSeconds = ${toString alertWindowSeconds}

        checkService :: Bool
        checkService = ${if checkService then "True" else "False"}

        data Event = Event
          { time :: Integer
          , event :: Text
          , summary :: Text
          , dnsNames :: [Text]
          , issuer :: Text
          }

        instance FromJSON Event where
          parseJSON = withObject "Event" $ \o ->
            Event
              <$> o .: "time"
              <*> o .:? "event" .!= ""
              <*> o .:? "summary" .!= ""
              <*> o .:? "dns_names" .!= []
              <*> o .:? "issuer" .!= ""

        -- 外部由来の文字列から行や見え方を崩す文字を除いて、Mackerelへ渡す1行に収める。
        -- Cc(制御文字)だけでなく、
        -- Cf(U+202Eのような双方向制御やゼロ幅文字)とU+2028/U+2029(行区切りと段落区切り)も、
        -- 通知上でドメイン名や発行者の見え方を偽装できるので空白にする。
        sanitize :: Text -> Text
        sanitize = T.map (\c -> if isUnsafe c then ' ' else c)
          where
            isUnsafe c = case generalCategory c of
              Control -> True
              Format -> True
              LineSeparator -> True
              ParagraphSeparator -> True
              _ -> False

        -- `event`はcertspotterが決める値だが、ログが壊れていた時のために同じ方針で扱う。
        render :: Event -> Text
        render e =
          T.unwords
            [ timestamp
            , sanitize (event e) <> ":"
            , sanitize (summary e)
            , "(" <> sanitize (T.intercalate "," (dnsNames e)) <> ")"
            , "issuer=" <> sanitize (issuer e)
            ]
          where
            timestamp = T.pack (formatTime defaultTimeLocale "%FT%TZ" (posixSecondsToUTCTime (fromInteger (time e))))

        critical :: [Text] -> IO ()
        critical messages = do
          mapM_ T.putStrLn messages
          exitWith (ExitFailure 2)

        main :: IO ()
        main = do
          hSetEncoding stdout utf8
          when checkService $ do
            (code, _, _) <- readProcessWithExitCode "${pkgs.systemd}/bin/systemctl" ["is-active", "--quiet", "certspotter.service"] ""
            unless (code == ExitSuccess) $ critical ["certspotter CRITICAL: service not running"]
          exists <- doesFileExist eventsLog
          if not exists
            then T.putStrLn "certspotter OK (no events yet)"
            else do
              now <- round <$> getPOSIXTime
              contents <- BS.readFile eventsLog
              -- 壊れた行は黙って飛ばす。
              -- 1行壊れているだけで監視全体が止まるよりは、残りの行を見られるほうが良い。
              let events = mapMaybe decodeStrict (BS.lines contents)
                  recent = filter (\e -> time e >= now - alertWindowSeconds) events
              if null recent
                then T.putStrLn "certspotter OK"
                else critical ("certspotter CRITICAL: new certificate transparency events" : map render recent)
      '';

  hook = mkHook { inherit eventsLog; };
  check = mkCheck {
    inherit eventsLog;
    checkService = true;
  };

  # hookが書いた行をチェックがそのまま読めることを、
  # 本物と同じソースから組んだ2つのプログラムで検査します。
  # ログはビルドディレクトリ相対のパスにして、systemdの状態確認は省きます。
  #
  # 検査するのは以下です。
  #
  # - ログが無ければOK
  # - タブや改行を含むイベントを記録しても、ログの行数とチェック出力の行数がイベント数と一致してCRITICAL
  # - 出力にタブや改行が漏れない
  # - 24時間より古いイベントだけならOK
  # - 壊れた行が混ざっても落ちない
  test =
    let
      testHook = lib.getExe (mkHook {
        eventsLog = "events.log";
      });
      testCheck = lib.getExe (mkCheck {
        eventsLog = "events.log";
        checkService = false;
      });
    in
    pkgs.runCommand "certspotter-hook-check-test" { } ''
      # チェックの終了コードと出力を取る。
      # `set -e`の下で非0を扱うため`if`で受ける。
      run_check() {
        if output=$(${testCheck}); then
          code=0
        else
          code=$?
        fi
      }

      run_check
      if [ "$code" -ne 0 ] || [ "$output" != "certspotter OK (no events yet)" ]; then
        echo "no-log: 期待 exit 0 'certspotter OK (no events yet)' 実際 exit $code '$output'" >&2
        exit 1
      fi

      # タブと改行に加えて、行区切り(U+2028)と双方向制御(U+202E)とゼロ幅空白(U+200B)も混ぜる。
      # UTF-8のバイト列で書いているのは、
      # bashの`$' '`がロケールに依存するため。
      echo '{"dns_names":["ncaq.net","*.ncaq.net"]}' > cert.json
      env EVENT=discovered_cert \
        SUMMARY=$'cert\tdiscovered\nfor\xe2\x80\xa8ncaq.net\xe2\x80\xae' \
        ISSUER_DN=$'CN=R12\tO=Evil\xe2\x80\x8b' \
        JSON_FILENAME="$PWD/cert.json" \
        ${testHook}
      env EVENT=error SUMMARY="log unreachable" ${testHook}
      # `event`はcertspotterが決める値だが、ログが壊れた時にも1行に収まることを見る。
      printf '{"time":%d,"event":"evil\\nevent","summary":"","dns_names":[],"issuer":""}\n' "$(date +%s)" >> events.log

      lines=$(wc -l < events.log)
      if [ "$lines" -ne 3 ]; then
        echo "record: 期待 3行 実際 ''${lines}行" >&2
        cat events.log >&2
        exit 1
      fi

      run_check
      output_lines=$(printf '%s\n' "$output" | wc -l)
      if [ "$code" -ne 2 ] || [ "$output_lines" -ne 4 ]; then
        echo "recent: 期待 exit 2 4行 実際 exit $code ''${output_lines}行" >&2
        printf '%s\n' "$output" >&2
        exit 1
      fi
      for forbidden in $'\t' $'\xe2\x80\xa8' $'\xe2\x80\xae' $'\xe2\x80\x8b'; do
        if printf '%s' "$output" | LC_ALL=C grep -q -F "$forbidden"; then
          echo "recent: 出力に制御文字が漏れています: $(printf '%s' "$forbidden" | od -An -tx1)" >&2
          printf '%s\n' "$output" >&2
          exit 1
        fi
      done
      if ! printf '%s' "$output" | grep -q 'ncaq.net,\*.ncaq.net'; then
        echo "recent: dns_namesが出力に含まれていません" >&2
        printf '%s\n' "$output" >&2
        exit 1
      fi

      old=$(( $(date +%s) - 2 * 24 * 60 * 60 ))
      printf '{"time":%d,"event":"discovered_cert","summary":"old","dns_names":[],"issuer":""}\n' "$old" > events.log
      echo 'not json' >> events.log
      run_check
      if [ "$code" -ne 0 ] || [ "$output" != "certspotter OK" ]; then
        echo "old-only: 期待 exit 0 'certspotter OK' 実際 exit $code '$output'" >&2
        exit 1
      fi

      touch "$out"
    '';
in
{
  # Certificate Transparencyログを監視して、
  # ncaq.net向けに発行された証明書を全て検知します。
  #
  # CAAレコードは真面目なCAの誤発行を防ぐだけで、
  # 秘密鍵が漏洩した中間CAによる発行(2026年10月のeMudhraの事件など)には無力です。
  # そのような発行はドメイン側で防げないので、
  # 代わりにCTログで検知して気づけるようにします。
  #
  # 発行元によるフィルタはしません。
  # ncaq.netの証明書はCloudflare Universal SSLとlegoの更新くらいで数が少なく、
  # 全件を目で見たほうが見落としが無いためです。
  services.certspotter = {
    enable = true;
    # 先頭の`.`でncaq.net自身と全てのサブドメインを対象にします。
    watchlist = [ ".ncaq.net" ];
    hooks = [ (lib.getExe hook) ];
  };

  # 検知したイベントは既存のMackerelの通知経路に乗せます。
  # mackerel-agentはrootで動くのでcertspotterのstateディレクトリを直接読めます。
  services.mackerel-agent.settings.plugin.checks.certspotter = {
    command = lib.getExe check;
    check_interval = 3;
    # イベントは一定期間残るので連続失敗の判定を待つ意味がなく、
    # すぐに通知を出します。
    max_check_attempts = 1;
  };

  # seminarのtoplevelをビルドする時に必ずテストも走らせます。
  system.checks = [ test ];
}
