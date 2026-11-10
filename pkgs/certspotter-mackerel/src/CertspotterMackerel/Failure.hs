-- | 想定している失敗の型。
module CertspotterMackerel.Failure
  ( ConfigFailure (..)
  ) where

import Himari

-- | 設定を揃えられない理由。
data ConfigFailure
  = -- | 必要な環境変数が無いか空である。その名前。
    MissingVariable Text
  | -- | アラート期間が整数の秒数ではない。その生の値。
    InvalidAlertWindow Text
  deriving stock (Eq, Show)

instance Exception ConfigFailure where
  displayException = \case
    MissingVariable name -> "環境変数" <> convert name <> "が必要です"
    InvalidAlertWindow raw ->
      "CERTSPOTTER_ALERT_WINDOW_SECONDSが0以上の整数ではありません: " <> convert raw
