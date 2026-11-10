-- | 購読するリモートのURL。
module GitRepoSubscribe.RemoteUrl
  ( RemoteUrl
  , parseRemoteUrl
  , remoteUrlText
  ) where

import Data.Text (isInfixOf)
import GitRepoSubscribe.Failure (RemoteUrlError (..))
import GitRepoSubscribe.UnsafeCharacter (hasUnsafeCharacter)
import Himari
import Network.URI (URI (..), URIAuth (..), parseURI, uriToString)

-- | `https`か`ssh`か`file`のスキームを持つGitのリモートのURL。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
-- 文字列ではなく解釈済みのURIで持つので、スキームやホストを検証した結果と中身がずれない。
newtype RemoteUrl = RemoteUrl URI
  deriving stock (Eq, Show)

-- | Gitへ渡す綴り。
--
-- `network-uri`は各部分を書かれた通りに保つので、検証に渡した綴りと一字も変わらない。
-- Gitが保存しているURLと文字列として比べられるのはそのためである。
remoteUrlText :: RemoteUrl -> Text
remoteUrlText (RemoteUrl uri) = convert (uriToString id uri "")

-- | リモートのURLを検証する。
--
-- 資格情報を含むURLは、プロセスの引数やログに残るので受け付けない。
-- SSHのユーザ名だけは接続先の一部なので通す。
--
-- スキームは小文字だけを受け付ける。
-- Gitは大文字のスキームを扱えず、Nix側の型検査も小文字しか通さない。
parseRemoteUrl :: Text -> Either RemoteUrlError RemoteUrl
parseRemoteUrl value
  | hasUnsafeCharacter value = Left UrlUnsafeCharacter
  | "\\" `isInfixOf` value = Left UrlBackslash
  | otherwise = do
      uri <- maybe (Left InvalidUrlSyntax) Right (parseURI (convert value))
      let scheme = takeWhile (/= ':') uri.uriScheme
      unless (scheme `elem` ["https", "ssh", "file"]) (Left (UnsupportedScheme (convert scheme)))
      -- `https:example.com/repo.git`のように`//`の無いURLも文法としては正しいが、
      -- 接続先が無いのでリモートとしては使えない。
      authority <- maybe (Left UrlMissingHost) Right uri.uriAuthority
      when (':' `elem` authority.uriUserInfo) (Left UrlPassword)
      when (scheme /= "ssh" && not (null authority.uriUserInfo)) (Left UrlUsername)
      -- `file:///path`はホストが空でも手元のファイルを指す。
      when (scheme /= "file" && null authority.uriRegName) (Left UrlMissingHost)
      pure (RemoteUrl uri)
