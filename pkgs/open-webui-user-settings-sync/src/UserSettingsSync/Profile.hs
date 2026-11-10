-- | プロフィールの宣言と、実体との比べ方。
--
-- `name`や`profile_image_url`のようなプロフィールの列は、設定とは受け口も表の列も別になる。
module UserSettingsSync.Profile
  ( desiredProfile
  , declaredColumns
  ) where

import Data.ByteString.Base64 qualified as Base64
import Himari
import UserSettingsSync.Object (objectOf)

-- | 宣言した列に、画像をdata URLにした`profile_image_url`を足す。
desiredProfile
  :: Map Text Value
  -- ^ 画像以外の宣言した列。
  -> ByteString
  -- ^ アイコンにするWebPの画像。
  -> Map Text Value
desiredProfile declared image =
  (mempty & at "profile_image_url" ?~ String dataUrl) <> declared
 where
  dataUrl = "data:image/webp;base64," <> convert (Base64.encode image)

-- | プロフィールの応答から、宣言した列だけを取り出す。
--
-- 比べる列を宣言の側から導く。
-- 応答には`email`や`role`のようにこちらが決めない列も並ぶので、
-- 固定で書くと宣言を増やした時に比較へ足し忘れる。
-- 応答に無い列は`null`として扱う。
declaredColumns
  :: Map Text Value
  -- ^ 宣言した列。
  -> Value
  -- ^ プロフィールの応答。
  -> Map Text Value
declaredColumns desired response = imap (\column _ -> fromMaybe Null (current ^? ix column)) desired
 where
  current = fromMaybe mempty (objectOf response)
