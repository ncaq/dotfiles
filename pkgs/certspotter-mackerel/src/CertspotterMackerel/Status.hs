-- | Mackerelのチェックの結果。
--
-- チェックプラグインは標準出力のメッセージと終了コードで結果を伝える。
-- <https://mackerel.io/ja/docs/entry/custom-checks>
module CertspotterMackerel.Status
  ( Status (..)
  , statusLines
  , statusExitCode
  , report
  ) where

import Data.ByteString qualified as B
import Himari

data Status
  = Ok Text
  | -- | 監視の一部が不調である。見出しと、イベントごとの行。
    Warning [Text]
  | -- | 人が確かめるべきイベントがある。見出しと、イベントごとの行。
    Critical [Text]
  | -- | 監視そのものができていない。OKにもCRITICALにもしない。
    Unknown Text
  deriving stock (Eq, Show)

-- | 標準出力へ出す行。
statusLines :: Status -> [Text]
statusLines = \case
  Ok message -> [message]
  Warning messages -> messages
  Critical messages -> messages
  Unknown message -> [message]

-- | Mackerelの規約の終了コード。
statusExitCode :: Status -> ExitCode
statusExitCode = \case
  Ok _ -> ExitSuccess
  Warning _ -> ExitFailure 1
  Critical _ -> ExitFailure 2
  Unknown _ -> ExitFailure 3

-- | 結果を標準出力へ出す。
--
-- これはログではなくMackerelが読む結果なので、ロガーを通さず標準出力へ直接書く。
-- mackerel-agentから呼ばれる時のロケールはUTF-8とは限らないので、
-- ロケールに従う文字列の出力ではなくUTF-8のバイト列として書く。
report :: (MonadIO m) => Status -> m ()
report status = liftIO (for_ (statusLines status) \line -> B.hPut stdout (convert line <> "\n"))
