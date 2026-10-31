{
  pkgs,
  lib,
  config,
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
  # unliftioは`IO`を直接書かずに`MonadIO`と`MonadUnliftIO`で抽象化するために使います。
  haskellLibraries = hpkgs: [
    hpkgs.aeson
    hpkgs.unliftio
  ];
  ghcArgs = [
    "-Wall"
    "-Wcompat"
    "-Widentities"
    "-Wincomplete-record-updates"
    "-Wincomplete-uni-patterns"
    "-Wpartial-fields"
    "-Wredundant-constraints"
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

        import Data.Aeson (eitherDecodeFileStrict', encode, object, withObject, (.!=), (.:?), (.=))
        import Data.Aeson.Types (Pair, parseEither)
        import Data.ByteString.Lazy qualified as BL
        import Data.Text (Text)
        import Data.Text qualified as T
        import Data.Time.Clock.POSIX (getPOSIXTime)
        import UnliftIO (IOMode (AppendMode), MonadUnliftIO, displayException, liftIO, tryIO, withBinaryFile)
        import UnliftIO.Environment (lookupEnv)

        eventsLog :: FilePath
        eventsLog = "${eventsLog}"

        -- 証明書のJSONから`dns_names`だけを取り出す。
        -- 読めなかった時はその理由を`Left`で返す。
        -- certspotterはhookが正常終了するとstderrを捨てるので、
        -- 理由は呼び出し側でログの行に残して、イベント自体の記録は止めない。
        dnsNamesOf :: (MonadUnliftIO m) => FilePath -> m (Either Text [Text])
        dnsNamesOf path = do
          -- `eitherDecodeFileStrict'`が`Left`にするのはパースの失敗だけで、
          -- ファイルが無いなどの読み取りの失敗はIOExceptionとして投げる。
          result <- tryIO (liftIO (eitherDecodeFileStrict' path))
          pure $ case result of
            Left exception -> Left (T.pack (displayException exception))
            Right decoded ->
              either (Left . T.pack) Right $
                decoded >>= parseEither (withObject "cert" (\o -> o .:? "dns_names" .!= []))

        main :: IO ()
        main = do
          event <- maybe "unknown" T.pack <$> lookupEnv "EVENT"
          summary <- maybe "" T.pack <$> lookupEnv "SUMMARY"
          issuer <- maybe "" T.pack <$> lookupEnv "ISSUER_DN"
          jsonFile <- lookupEnv "JSON_FILENAME"
          dnsNamesResult <- case jsonFile of
            Just path | event == "discovered_cert" -> dnsNamesOf path
            _ -> pure (Right [])
          now <- round <$> getPOSIXTime :: IO Integer
          -- 読めなかった理由は握り潰さずに`dns_names_error`として同じ行に残す。
          let (dnsNames, dnsNamesError) = case dnsNamesResult of
                Right names -> (names, [])
                Left reason -> ([], ["dns_names_error" .= reason] :: [Pair])
              record =
                object $
                  [ "time" .= now
                  , "event" .= event
                  , "summary" .= summary
                  , "dns_names" .= dnsNames
                  , "issuer" .= issuer
                  ]
                    ++ dnsNamesError
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
        import System.Exit (ExitCode (ExitFailure, ExitSuccess), exitWith)
        import System.IO (hSetEncoding, utf8)
        import UnliftIO (MonadIO, liftIO, stdout)
        import UnliftIO.Directory (doesFileExist)
        import UnliftIO.Process (readProcessWithExitCode)

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
          , -- hookが証明書のJSONを読めなかった時の理由。
            dnsNamesError :: Maybe Text
          }

        instance FromJSON Event where
          parseJSON = withObject "Event" $ \o ->
            Event
              <$> o .: "time"
              <*> o .:? "event" .!= ""
              <*> o .:? "summary" .!= ""
              <*> o .:? "dns_names" .!= []
              <*> o .:? "issuer" .!= ""
              <*> o .:? "dns_names_error"

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
          T.unwords $
            [ timestamp
            , sanitize (event e) <> ":"
            , sanitize (summary e)
            , "(" <> sanitize (T.intercalate "," (dnsNames e)) <> ")"
            , "issuer=" <> sanitize (issuer e)
            ]
              ++ maybe [] (\reason -> ["dns_names_error=" <> sanitize reason]) (dnsNamesError e)
          where
            timestamp = T.pack (formatTime defaultTimeLocale "%FT%TZ" (posixSecondsToUTCTime (fromInteger (time e))))

        -- Mackerelの規約どおり、メッセージを出してからexit 2で終わる。
        -- 戻ってこないので任意の`m a`として呼べる。
        critical :: (MonadIO m) => [Text] -> m a
        critical messages = liftIO $ do
          mapM_ T.putStrLn messages
          exitWith (ExitFailure 2)

        main :: IO ()
        main = do
          hSetEncoding stdout utf8
          when checkService $ do
            (code, _, _) <- readProcessWithExitCode "${lib.getExe' config.systemd.package "systemctl"}" ["is-active", "--quiet", "certspotter.service"] ""
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
  # - タブや改行や行区切りなどを含むイベントを記録しても、
  #   ログの行数はイベント数と一致し、
  #   チェック出力は見出し1行とイベントごとに1行でCRITICAL
  # - 出力にタブや行区切りや双方向制御やゼロ幅文字が漏れない
  # - 証明書のJSONが読めなくてもhookは落ちず、
  #   `dns_names`を空にして理由を`dns_names_error`に残し、チェックの出力にも出る
  # - アラート期間(`alertWindowSeconds`)より古いイベントだけならOK
  # - 壊れた行が混ざっても落ちない
  # - 古いイベントと新しいイベントが混ざっていたら新しいものだけを出してCRITICAL
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

      # `dnsNamesOf`が証明書のJSONを読めない時に、
      # `dns_names`を空にしてイベント自体は記録することを見る。
      echo 'not json' > broken.json
      echo '{"dns_names":"ncaq.net"}' > not-array.json
      : > events.log
      for json in "$PWD/missing.json" "$PWD/broken.json" "$PWD/not-array.json"; do
        if ! env EVENT=discovered_cert SUMMARY="unreadable cert json" JSON_FILENAME="$json" ${testHook}; then
          echo "unreadable-json: hookが非0で終了しました: $json" >&2
          exit 1
        fi
      done
      lines=$(wc -l < events.log)
      empty_lines=$(grep -c -F '"dns_names":[]' events.log || true)
      error_lines=$(grep -c -F '"dns_names_error":' events.log || true)
      if [ "$lines" -ne 3 ] || [ "$empty_lines" -ne 3 ] || [ "$error_lines" -ne 3 ]; then
        echo "unreadable-json: 期待 3行とも dns_names が空で dns_names_error あり 実際 ''${lines}行中 空''${empty_lines}行 理由''${error_lines}行" >&2
        cat events.log >&2
        exit 1
      fi
      run_check
      if [ "$code" -ne 2 ] || ! printf '%s' "$output" | grep -q -F 'dns_names_error='; then
        echo "unreadable-json: 期待 exit 2 で出力に dns_names_error= を含む 実際 exit $code" >&2
        printf '%s\n' "$output" >&2
        exit 1
      fi

      # アラート期間より古い行と壊れた行だけなら、黙ってOKになることを見る。
      old=$(( $(date +%s) - 2 * ${toString alertWindowSeconds} ))
      printf '{"time":%d,"event":"discovered_cert","summary":"old","dns_names":[],"issuer":""}\n' "$old" > events.log
      echo 'not json' >> events.log
      run_check
      if [ "$code" -ne 0 ] || [ "$output" != "certspotter OK" ]; then
        echo "old-only: 期待 exit 0 'certspotter OK' 実際 exit $code '$output'" >&2
        exit 1
      fi

      # 古い行と新しい行が混ざっている時に、新しい行だけを出すことを見る。
      printf '{"time":%d,"event":"discovered_cert","summary":"fresh","dns_names":[],"issuer":""}\n' "$(date +%s)" >> events.log
      run_check
      output_lines=$(printf '%s\n' "$output" | wc -l)
      if [ "$code" -ne 2 ] || [ "$output_lines" -ne 2 ]; then
        echo "mixed: 期待 exit 2 2行 実際 exit $code ''${output_lines}行" >&2
        printf '%s\n' "$output" >&2
        exit 1
      fi
      if printf '%s' "$output" | grep -q -F 'old' || ! printf '%s' "$output" | grep -q -F 'fresh'; then
        echo "mixed: 古いイベントが混ざっているか、新しいイベントが欠けています" >&2
        printf '%s\n' "$output" >&2
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
