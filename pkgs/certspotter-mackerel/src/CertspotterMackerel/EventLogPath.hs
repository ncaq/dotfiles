-- | イベントのログのパス。
--
-- hookとチェックは証明書のJSONのパスも扱うので、取り違えないように型を分ける。
module CertspotterMackerel.EventLogPath
  ( EventLogPath (..)
  ) where

import Himari

newtype EventLogPath = EventLogPath FilePath
  deriving stock (Eq, Show)
  deriving newtype (IsString)
