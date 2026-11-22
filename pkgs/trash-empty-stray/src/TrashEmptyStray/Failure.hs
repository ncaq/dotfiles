-- | 想定している失敗の型。
module TrashEmptyStray.Failure
  ( CleanFailure (..)
  , OwnerFailure (..)
  ) where

import Himari

-- | ゴミ箱を掃除できない理由。
newtype CleanFailure
  = -- | `trash-empty`が失敗した。その終了コード。
    TrashEmptyFailed ExitCode
  deriving stock (Eq, Show)

instance Exception CleanFailure where
  displayException = \case
    TrashEmptyFailed code -> "trash-emptyが失敗しました: " <> show code

-- | 所有者の権限でのコマンドの実行が失敗した理由。
newtype OwnerFailure
  = -- | 所有者の権限で起動したコマンドが成功で終わらなかった。その終了コード。
    ChildFailed ExitCode
  deriving stock (Eq, Show)

instance Exception OwnerFailure where
  displayException = \case
    ChildFailed code -> "所有者の権限で起動したコマンドが失敗しました: " <> show code
