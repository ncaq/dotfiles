#!/usr/bin/env nix-shell
#! nix-shell -i runghc
#! nix-shell -p android-tools
#! nix-shell -p "haskellPackages.ghcWithPackages (p: [ p.megaparsec p.typed-process ])"
{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- adbで繋がっているAndroid端末のハードウェア情報を、
-- `hardware.md`へそのまま貼れるMarkdownのリストとして出す。
--
-- 端末の中でfastfetchを動かすと、
-- nix-on-droidのprootの層を挟むので見えない情報が多く、
-- 出力を手で直す必要があった。
-- adbならAndroidが持っている値を直接読める。
--
-- USBデバッグを許可した端末を繋いで、引数無しで実行する。
-- 複数の端末が繋がっていれば全ての端末の分を出す。
--
-- 端末やAndroidのバージョンによって読めない値がある。
-- 読めなかった項目は標準エラー出力に理由を書いて、その行だけを省く。
--
-- nix-shellから単独で動かすスクリプトなので、
-- `pkgs`のパッケージと違ってhimariは使っていない。
-- himariはstableのnixpkgsには無く、flakeのoverlayを通さないと手に入らない。
module Main (main) where

import Control.Monad (when)
import Data.Char (isSpace)
import Data.Foldable (find)
import Data.List (sortOn)
import Data.Maybe (catMaybes, fromMaybe, isNothing)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding.Error (lenientDecode)
import Data.Text.IO qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TL
import Data.Void (Void)
import System.Exit (ExitCode (..), exitFailure)
import System.IO (stderr)
import System.Process.Typed (proc, readProcess)
import Text.Megaparsec
  ( Parsec
  , anySingle
  , parseMaybe
  , sepBy1
  , skipManyTill
  , some
  , takeRest
  , takeWhile1P
  , takeWhileP
  , try
  )
import Text.Megaparsec.Char (char, eol, hspace1, string)
import Text.Megaparsec.Char.Lexer qualified as L
import Text.Printf (printf)

type Parser = Parsec Void Text

-- | `adb devices`が返す、端末を指し示す識別子。
newtype Serial = Serial Text

main :: IO ()
main = do
  serials <- connectedDevices
  when (null serials) do
    warn "使える端末が繋がっていません"
    exitFailure
  blocks <- traverse describe serials
  T.putStr (T.intercalate "\n" (T.unlines <$> blocks))

warn :: Text -> IO ()
warn message = T.hPutStrLn stderr ("android-fetch-hardware: " <> message)

-- | adbを実行して標準出力を返す。失敗した時は理由を書いて`Nothing`を返す。
adb :: [Text] -> IO (Maybe Text)
adb args = do
  (code, out, err) <- readProcess (proc "adb" (T.unpack <$> args))
  case code of
    ExitSuccess -> pure (Just (decode out))
    ExitFailure status -> do
      warn
        ( T.unwords ("adb" : args)
            <> " が終了コード"
            <> T.show status
            <> "で失敗しました: "
            <> T.strip (decode err)
        )
      pure Nothing
 where
  -- 端末が返すバイト列がUTF-8として壊れていても、読める所までは読む。
  decode = TL.toStrict . TL.decodeUtf8With lenientDecode

-- | 操作を受け付ける状態で繋がっている端末の一覧。
connectedDevices :: IO [Serial]
connectedDevices = do
  output <- adb ["devices"]
  catMaybes <$> traverse device (drop 1 (T.lines (fromMaybe "" output)))
 where
  device row = case T.words row of
    [serial, "device"] -> pure (Just (Serial serial))
    (serial : state) -> do
      -- USBデバッグを許可していない端末は`unauthorized`になる。
      -- udevの設定が足りない時は`no permissions (...)`のように複数の語になる。
      warn (serial <> " は " <> T.unwords state <> " の状態なので読めません")
      pure Nothing
    [] -> pure Nothing

-- | 端末の中でコマンドを実行する。空の出力は値が無いものとして扱う。
shell :: Serial -> Text -> IO (Maybe Text)
shell (Serial serial) command = (>>= nonEmpty . T.strip) <$> adb ["-s", serial, "shell", command]
 where
  nonEmpty text = if T.null text then Nothing else Just text

-- | 端末の中でコマンドを実行して、出力をパーサで読む。
query :: Serial -> Text -> Parser a -> IO (Maybe a)
query serial command parser =
  shell serial command >>= maybe (pure Nothing) (parseOrWarn command parser)

parseOrWarn :: Text -> Parser a -> Text -> IO (Maybe a)
parseOrWarn source parser text = case parseMaybe (parser <* takeRest) text of
  Nothing -> do
    warn (source <> " の出力を解釈できませんでした")
    pure Nothing
  found -> pure found

-- | パーサが合う最初の場所まで読み飛ばす。
seek :: Parser a -> Parser a
seek parser = skipManyTill anySingle (try parser)

-- | 1つの端末の情報を、Markdownのリストの行として組み立てる。
describe :: Serial -> IO [Text]
describe serial =
  concat
    <$> sequence
      [ one "Name" (setting "device_name")
      , one "Product" (setting "default_device_name")
      , one "Host" (props ["ro.product.manufacturer", "ro.product.model"])
      , one "OS" os
      , one "Kernel" (fmap ("Linux " <>) <$> shell serial "uname -r")
      , one "CPU" cpu
      , one "GPU" gpu
      , memory
      , one "Disk (/data)" disk
      , displays
      , one "Battery" battery
      ]
 where
  item label value = "- " <> label <> ": " <> value
  one label action = foldMap (\value -> [item label value]) <$> action
  getprop name = shell serial ("getprop " <> name)
  props names = joinWords <$> traverse getprop names
  -- 設定に値が無い時は`null`という文字列が返る。
  setting name =
    (>>= \value -> if value == "null" then Nothing else Just value)
      <$> shell serial ("settings get global " <> name)

  os = do
    release <- getprop "ro.build.version.release"
    sdk <- getprop "ro.build.version.sdk"
    oneUi <- getprop "ro.build.version.oneui"
    pure do
      version <- release
      pure
        ( T.intercalate
            ", "
            ( catMaybes
                [ Just ("Android " <> version <> maybe "" (\level -> " (SDK " <> level <> ")") sdk)
                , ("One UI " <>) <$> (oneUi >>= parseMaybe oneUiVersion)
                ]
            )
        )

  cpu = do
    maker <- getprop "ro.soc.manufacturer"
    model <- getprop "ro.soc.model"
    -- 同じ型番でも`for Galaxy`のような派生があり、Qualcommではこの符号で区別できる。
    -- 他のメーカーのSoCではこのファイルを読めないので、Qualcommの時だけ読む。
    featureCode <-
      if maker == Just "QTI"
        then shell serial "cat /sys/devices/soc0/feature_code"
        else pure Nothing
    let partNumber = T.intercalate "-" . catMaybes . (: [featureCode]) . Just <$> model
        known = partNumber >>= (`lookup` socNames)
    when (isNothing known) do
      warn (fromMaybe "不明なSoC" partNumber <> " の商品名を知らないので型番で出します。socNamesに足してください")
    let soc = case (known, partNumber) of
          (Just name, Just part) -> Just (name <> " [" <> part <> "]")
          _ -> joinWords [maker, partNumber]
    -- 最大周波数が同じコアをcpufreqのpolicyがまとめているので、policyごとに1行で読む。
    clusters <-
      query
        serial
        ( "cd /sys/devices/system/cpu/cpufreq && for p in policy*; do "
            <> "echo \"$(cat $p/cpuinfo_max_freq) $(cat $p/related_cpus)\"; done"
        )
        (some cluster)
    pure (joinWords [soc, formatClusters <$> clusters])

  -- SurfaceFlingerが使っているドライバの自己申告を読む。
  gpu = query serial "dumpsys SurfaceFlinger | grep '^GLES: '" glesLine

  memory = do
    info <-
      query
        serial
        "cat /proc/meminfo"
        ((,) <$> meminfoField "MemTotal" <*> meminfoField "SwapTotal")
    pure case info of
      Nothing -> []
      Just (total, swap) ->
        item "Memory" (formatKib total <> foldMap formatNominal (nominalMemoryGb total))
          -- スワップを持たない端末では行ごと省く。
          : [item "Swap" (formatKib swap) | swap > 0]
  formatNominal gb = " (nominal " <> T.show gb <> " GB)"

  disk = do
    usage <- query serial "df -k /data" dfRow
    filesystem <- shell serial "stat -f -c %T /data"
    pure (formatUsage <$> usage <*> filesystem)

  displays = do
    output <- shell serial "dumpsys display | grep 'DisplayDeviceInfo{'"
    found <-
      catMaybes
        <$> traverse (parseOrWarn "dumpsys display" displayRow) (T.lines (fromMaybe "" output))
    pure case found of
      [single] -> [item "Display" (formatDisplay single)]
      many -> zipWith numbered [1 :: Int ..] many
  numbered index info = item ("Display " <> T.show index) (formatDisplay info)

  -- 設計容量はrootが無いと読めないので、Androidの見積もりを使う。
  battery =
    fmap (\capacity -> T.show capacity <> " mAh")
      <$> query
        serial
        "dumpsys batterystats | grep 'Estimated battery capacity'"
        (seek batteryCapacity)

-- | 取れた値だけを空白で繋ぐ。全て取れなかった時は`Nothing`にする。
joinWords :: [Maybe Text] -> Maybe Text
joinWords parts = case catMaybes parts of
  [] -> Nothing
  found -> Just (T.unwords found)

-- | `ro.build.version.oneui`の`90000`を`9.0`、`60101`を`6.1`と読む。
oneUiVersion :: Parser Text
oneUiVersion = format <$> L.decimal
 where
  format :: Int -> Text
  format number = T.show (number `div` 10000) <> "." <> T.show (number `div` 100 `mod` 100)

-- | 最大周波数が同じコアのまとまり。
data Cluster = Cluster
  { maxFrequencyKhz :: Int
  , cores :: Int
  }

-- | `3532800 0 1 2 3 4 5`のような、最大周波数とコア番号の並び。
cluster :: Parser Cluster
cluster =
  Cluster
    <$> L.decimal
    <*> (length <$> some (hspace1 *> (L.decimal :: Parser Int)))
    <* takeWhileP Nothing isSpace

-- | `(8) 2x 4.47 GHz + 6x 3.53 GHz`のように、速いコアから並べる。
formatClusters :: [Cluster] -> Text
formatClusters clusters =
  "("
    <> T.show (sum ((.cores) <$> clusters))
    <> ") "
    <> T.intercalate " + " (formatCluster <$> sortOn (Down . (.maxFrequencyKhz)) clusters)
 where
  formatCluster c =
    T.show c.cores
      <> "x "
      <> T.pack (printf "%.2f" (fromIntegral c.maxFrequencyKhz / 1e6 :: Double))
      <> " GHz"

-- | SoCの型番から商品名を引く表。
-- 商品名は端末のどこにも書かれていないので、持っている端末の分を手で持つ。
-- 知らない型番は型番のまま出して、標準エラー出力で知らせる。
socNames :: [(Text, Text)]
socNames =
  [ ("MT6993", "MediaTek Dimensity 9500")
  , ("SM8550-AC", "Qualcomm Snapdragon 8 Gen 2 for Galaxy")
  , ("SM8750-AC", "Qualcomm Snapdragon 8 Elite for Galaxy")
  ]

-- | `GLES: Qualcomm, Adreno (TM) 830, OpenGL ES 3.2 V@0800.64.8 (GIT@...)`から、
-- ベンダとGPUの名前を`Qualcomm Adreno (TM) 830`として読む。
glesLine :: Parser Text
glesLine = (\vendor renderer -> vendor <> " " <> renderer) <$> (string "GLES: " *> field) <*> field
 where
  field = takeWhile1P Nothing (/= ',') <* string ", "

-- | `/proc/meminfo`の`MemTotal:       15453036 kB`からKiB単位の数値を読む。
meminfoField :: Text -> Parser Int
meminfoField name = seek (string (name <> ":") *> hspace1 *> L.decimal <* string " kB")

-- | 搭載メモリの公称値。
-- カーネルやファームウェアが予約する分だけ`MemTotal`は小さく見えるので、
-- 製品として売られている容量のうち、見えている量を下回らない最小のものを選ぶ。
-- メモリの「16 GB」は実際には16 GiBなので、2進接頭辞で比べる。
-- 10進で比べると、予約が少なく16 GBを超えて見える端末を1つ上の容量と誤る。
nominalMemoryGb :: Int -> Maybe Int
nominalMemoryGb kib =
  find (\gb -> gb * 1024 * 1024 >= kib) [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]

data Usage = Usage
  { totalKib :: Int
  , usedKib :: Int
  }

-- | `df -k`の見出しの次の行から、全体と使用量を読む。
dfRow :: Parser Usage
dfRow =
  seek
    ( eol
        *> takeWhile1P Nothing (not . isSpace)
        *> (Usage <$> (hspace1 *> L.decimal) <*> (hspace1 *> L.decimal))
    )

formatUsage :: Usage -> Text -> Text
formatUsage usage filesystem =
  formatKib usage.usedKib
    <> " / "
    <> formatKib usage.totalKib
    <> T.pack (printf " (%.0f%%) - " percent)
    <> filesystem
 where
  percent = fromIntegral usage.usedKib / fromIntegral usage.totalKib * 100 :: Double

-- | fastfetchに合わせて2進接頭辞で書く。
formatKib :: Int -> Text
formatKib kib
  | gib >= 1024 = T.pack (printf "%.2f TiB" (gib / 1024))
  | otherwise = T.pack (printf "%.2f GiB" gib)
 where
  gib = fromIntegral kib / 1024 / 1024 :: Double

data Display = Display
  { width :: Int
  , height :: Int
  , refreshRates :: [Double]
  , xdpi :: Double
  , ydpi :: Double
  }

-- | `dumpsys display`の`DisplayDeviceInfo{...}`の行から、解像度とリフレッシュレートと画素密度を読む。
displayRow :: Parser Display
displayRow =
  Display
    <$> (seek (string "uniqueId=\"" *> takeWhileP Nothing (/= '"') *> string "\", ") *> L.decimal)
    <*> (string " x " *> L.decimal)
    <*> seek (string "supportedRefreshRates [" *> (L.float `sepBy1` string ", ") <* char ']')
    <*> seek (string "density " *> (L.decimal :: Parser Int) *> string ", " *> L.float)
    <*> (string " x " *> L.float <* string " dpi")

-- | 対角のインチ数は端末が直接は教えてくれないので、解像度と画素密度から求める。
formatDisplay :: Display -> Text
formatDisplay display =
  T.pack
    ( printf
        "%dx%d in %.1f\", %.0f Hz"
        display.width
        display.height
        ( sqrt
            ( (fromIntegral display.width / display.xdpi) ^ (2 :: Int)
                + (fromIntegral display.height / display.ydpi) ^ (2 :: Int)
            )
        )
        (maximum display.refreshRates)
    )

batteryCapacity :: Parser Int
batteryCapacity = string "Estimated battery capacity: " *> L.decimal <* string " mAh"
