-- | `/proc/self/mountinfo`の読み取り。
--
-- ディレクトリがどのファイルシステムの上にあるかを調べるために使う。
-- 形式は`proc_pid_mountinfo(5)`に書いてある。
module NixCachePushNcaq.MountInfo
  ( Mount (..)
  , parseMountInfo
  , fileSystemOf
  ) where

import Data.List (isPrefixOf, sortOn)
import Himari
import NixCachePushNcaq.Failure (ConfigFailure (..))
import Text.Megaparsec hiding (many, some)
import Text.Megaparsec.Char

-- | マウントされているファイルシステムの1つ。
data Mount = Mount
  { mountPoint :: FilePath
  , fileSystem :: Text
  -- ^ `tmpfs`や`btrfs`のような種類の名前。
  }
  deriving stock (Eq, Show)

type Parser = Parsec Void Text

-- | mountinfoの中身を読む。読めなければ`UnparsableMountInfo`を投げる。
parseMountInfo :: (MonadThrow m) => Text -> m [Mount]
parseMountInfo =
  either (throwM . UnparsableMountInfo . convert . errorBundlePretty) pure
    . runParser (mount `sepEndBy` newline <* eof) "mountinfo"

-- | 1行を読む。
--
-- 欄は空白で区切られていて、5番目がマウントポイントである。
-- その後ろにマウントのオプションと個数の決まっていない任意の欄が続き、
-- `-`の次にファイルシステムの種類が来る。
mount :: Parser Mount
mount =
  Mount
    <$> (count 4 field *> some pathChar <* char ' ')
    <*> (field *> manyTill field (string "- ") *> word <* takeWhileP Nothing (/= '\n'))
 where
  field = word <* char ' '
  word = takeWhile1P (Just "field") (\c -> c /= ' ' && c /= '\n')

-- | マウントポイントの1文字を読む。
--
-- カーネルは空白や改行やバックスラッシュを、`\\040`のような3桁の8進数で書く。
pathChar :: Parser Char
pathChar = escaped <|> satisfy (\c -> c /= ' ' && c /= '\n' && c /= '\\')
 where
  escaped = do
    digits <- char '\\' *> count 3 octDigitChar
    maybe (fail "invalid octal escape") pure (preview (_head . _1) (readOct digits) >>= chrMay)

-- | パスが載っているファイルシステムの種類を返す。
--
-- パスを含むマウントのうち、マウントポイントが最も深いものを選ぶ。
-- 同じマウントポイントに重ねてマウントされていれば、後の行が上に載っているのでそれを選ぶ。
-- パスは`canonicalizePath`を通した絶対パスで渡す。
fileSystemOf :: [Mount] -> FilePath -> Maybe Text
fileSystemOf mounts path =
  preview (_last . to (.fileSystem)) (sortOn depth (filter covers mounts))
 where
  components = splitDirectories path
  covers candidate = splitDirectories candidate.mountPoint `isPrefixOf` components
  depth candidate = length (splitDirectories candidate.mountPoint)
