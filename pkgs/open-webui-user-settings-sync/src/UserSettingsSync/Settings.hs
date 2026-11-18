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
import UserSettingsSync.Object (objectOf)

-- | 設定の応答から今の`ui`を取り出す。
--
-- 利用者の設定が一度も書かれていなければ応答は`null`になる。
-- `ui`が無い時も含めて、オブジェクトでなければ空として扱う。
currentUi :: Value -> Map Text Value
currentUi response = fromMaybe mempty (objectOf response >>= (^? ix "ui") >>= objectOf)

-- | 今の`ui`へ宣言した鍵だけを重ねて、システムプロンプトも合わせる。
--
-- 全置換にしないのは、最後に選んだModelを覚える`models`のように、
-- 人が触った結果をそのまま持たせたい鍵が同じ階層に同居しているためである。
--
-- システムプロンプトだけは、宣言が無ければ今の値を保たずに取り除く。
-- 宣言をやめた時に、以前の同期が書き込んだ値がDBへ残り続けるのを防ぐためである。
--
-- システムプロンプトの末尾の改行を1つ落とすのは、UIのテキストエリアが持つ値と揃えるためで、
-- 人が入力欄で書いた場合は末尾に改行が付かない。
mergeUi
  :: Map Text Value
  -- ^ 今の`ui`。
  -> Map Text Value
  -- ^ 宣言した鍵。
  -> Maybe Text
  -- ^ システムプロンプト。無ければ持たないという宣言。
  -> Map Text Value
mergeUi current declared systemPrompt =
  -- `Map`の`<>`は左を優先するので、強いものを左に置く。
  (declared <> current) & at "system" .~ (String . trimmed <$> systemPrompt)
 where
  trimmed text = fromMaybe text (T.stripSuffix "\n" text)
