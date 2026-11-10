-- | 購読するリモートのURL。
module GitRepoSubscribe.RemoteUrl
  ( RemoteUrl
  , parseRemoteUrl
  , remoteUrlText
  ) where

import Data.Char (toLower)
import Data.Text (isInfixOf)
import GitRepoSubscribe.Failure (RemoteUrlError (..))
import GitRepoSubscribe.UnsafeCharacter (hasUnsafeCharacter)
import Himari
import Network.URI (URI (..), URIAuth (..), parseURI)

-- | `https`か`ssh`か`file`のスキームを持つGitのリモートのURL。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
-- Gitが保存しているURLと文字列として比べるので、渡された綴りのまま持つ。
newtype RemoteUrl = RemoteUrl Text
  deriving stock (Eq, Show)

-- | Gitへ渡す、検証済みの元の綴り。
remoteUrlText :: RemoteUrl -> Text
remoteUrlText (RemoteUrl value) = value

-- | リモートのURLを検証する。
--
-- 資格情報を含むURLは、プロセスの引数やログに残るので受け付けない。
-- SSHのユーザ名だけは接続先の一部なので通す。
parseRemoteUrl :: Text -> Either RemoteUrlError RemoteUrl
parseRemoteUrl value
  | hasUnsafeCharacter value = Left UrlUnsafeCharacter
  | "\\" `isInfixOf` value = Left UrlBackslash
  | otherwise = do
      uri <- maybe (Left InvalidUrlSyntax) Right (parseURI (convert value))
      let scheme = toLower <$> takeWhile (/= ':') uri.uriScheme
          userInfo = maybe "" (.uriUserInfo) uri.uriAuthority
      unless (scheme `elem` ["https", "ssh", "file"]) (Left (UnsupportedScheme (convert scheme)))
      when (':' `elem` userInfo) (Left UrlPassword)
      when (scheme /= "ssh" && not (null userInfo)) (Left UrlUsername)
      pure (RemoteUrl value)
