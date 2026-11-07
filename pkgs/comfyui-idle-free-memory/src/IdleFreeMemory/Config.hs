-- | 起動時に受け取る設定と、その読み方。
--
-- 環境変数の値をどう解釈するかをここに置き、
-- 境界値をテストで固定できるようにする。
-- 環境変数を実際に読むのは`app/Main.hs`だけである。
module IdleFreeMemory.Config
  ( Config (..)
  , parseSeconds
  , requestFor
  , validAuthority
  ) where

import Data.Char (isDigit)
import Himari
import Network.HTTP.Client (host, port)
import Network.HTTP.Simple (Request, parseRequest)

-- | 起動時に受け取る設定。
data Config = Config
  { authority :: Text
  -- ^ ComfyUIの`host:port`。
  , pollIntervalSeconds :: Int
  -- ^ 確認の間隔。
  , idleThreshold :: NominalDiffTime
  -- ^ これだけ何もしていなければ解放する。
  }
  deriving stock (Eq, Show)

-- | 秒数を正の整数として読む。
--
-- 読めない値で動き出すと、待たずに回り続けるか永久に解放しないかのどちらかになるので、
-- 呼び出し側は`Nothing`なら起動の時点で落とす。
--
-- 受け付けるのはASCIIの数字だけの文字列にする。
-- `Read`に任せると前後の空白を読み飛ばすので、
-- 設定の書き損じが黙って通ってしまう。
--
-- 待ちは`threadDelay`へマイクロ秒で渡すので、
-- それが`Int`に収まらない値も弾く。
-- `Int`として読むと桁あふれで黙って違う値になるので、
-- 一度`Integer`として読んでから範囲を確かめる。
parseSeconds :: String -> Maybe Int
parseSeconds raw = do
  -- `isDigit`はASCIIの数字だけを真にする。
  guard (not (null raw) && all isDigit raw)
  seconds :: Integer <- readMay raw
  guard (0 < seconds && seconds <= toInteger (maxBound :: Int) `div` 1000000)
  pure (fromInteger seconds)

-- | ComfyUIへの要求を組み立てる。
--
-- 環境変数から受け取るのはホストとポートだけで、スキームはここで固定する。
-- 実際の要求も起動時の検査もここを通すので、
-- 組み立て方を変えても検査と要求がずれない。
requestFor :: (MonadThrow m) => Text -> Text -> m Request
requestFor authority path = parseRequest (convert ("http://" <> authority <> path))

-- | 接続先として要求を組み立てられるか。
--
-- 壊れていると全ての周回が同じ理由で失敗し続けるので、
-- 呼び出し側は偽なら起動の時点で落とす。
--
-- `parseRequest`はホストが空の`""`や`":8188"`も、範囲外のポートも通すので、
-- 組み立てた要求のホストとポートも確かめる。
validAuthority :: Text -> Bool
validAuthority authority = case requestFor authority "/" of
  Just request -> host request /= mempty && 0 < port request && port request <= 65535
  Nothing -> False
