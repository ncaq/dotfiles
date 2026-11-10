-- | 利用者の設定のマージ。
--
-- 利用者の設定は`user`表の`settings`列に入る自由形式のJSONで、
-- UIの挙動は`ui`の下に並んでいる。
module UserSettingsSync.Settings
  ( currentUi
  , mergeUi
  ) where

import Data.Text qualified as T
import Himari

-- | 設定の応答から今の`ui`を取り出す。
--
-- 利用者の設定が一度も書かれていなければ応答は`null`になる。
-- `ui`が無い時も含めて、オブジェクトでなければ空として扱う。
currentUi :: Value -> Map Text Value
currentUi response = fromMaybe mempty (objectOf response >>= (^? ix "ui") >>= objectOf)
 where
  objectOf :: Value -> Maybe (Map Text Value)
  objectOf value = case fromJSON value of
    Success object -> Just object
    Error _ -> Nothing

-- | 今の`ui`へ宣言した鍵だけを重ねて、システムプロンプトも合わせる。
--
-- 全置換にしないのは、最後に選んだModelを覚える`models`のように、
-- 人が触った結果をそのまま持たせたい鍵が同じ階層に同居しているためである。
--
-- システムプロンプトの末尾の改行を1つ落とすのは、UIのテキストエリアが持つ値と揃えるためで、
-- 人が入力欄で書いた場合は末尾に改行が付かない。
mergeUi
  :: Map Text Value
  -- ^ 今の`ui`。
  -> Map Text Value
  -- ^ 宣言した鍵。
  -> Text
  -- ^ システムプロンプト。
  -> Map Text Value
mergeUi current declared systemPrompt =
  -- `Map`の`<>`は左を優先するので、強いものを左に置く。
  (mempty & at "system" ?~ String trimmed) <> declared <> current
 where
  trimmed = fromMaybe systemPrompt (T.stripSuffix "\n" systemPrompt)
