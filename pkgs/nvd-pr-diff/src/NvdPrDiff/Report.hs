-- | `nvd diff`の出力を構造にする。
--
-- nvdは人が読むための行を出すだけで、機械向けの形式を持たない。
-- 行の形はnvdの`print_packages`が決めていて、
--
-- > [U.]  #01  foo  1.0 -> 1.1, 1.2 x2
--
-- のように、状態、通し番号、パッケージ名、バージョンの並びである。
-- 状態の1文字目は閉包の中でどう変わったか、2文字目は`environment.systemPackages`に選ばれているかで、
-- 対応表は'installStateCode'と'selectionStateCode'にある。
-- バージョンが複数ある時は`, `で並び、同じものが続く分は` xN`でまとまる。
-- 色は標準出力が端末でなければ付かないが、念のため呼ぶ側で`--color never`を渡している。
module NvdPrDiff.Report
  ( Report (..)
  , Section (..)
  , SectionKind (..)
  , Package (..)
  , InstallState (..)
  , installStateCode
  , SelectionState (..)
  , selectionStateCode
  , Version (..)
  , ClosureSize (..)
  , ReportFailure (..)
  , parseReport
  ) where

import Himari
import Text.Megaparsec hiding (many, some)
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer (decimal, signed)

-- | `nvd diff`の出力の全体。
data Report = Report
  { before :: Text
  -- ^ 比較元のstore path。
  , after :: Text
  -- ^ 比較先のstore path。
  , sections :: [Section]
  -- ^ 変化の種類ごとの一覧。何も変わっていなければ空。
  , closure :: ClosureSize
  }
  deriving stock (Eq, Show)

-- | 変化の種類1つ分の一覧。
data Section = Section
  { kind :: SectionKind
  , packages :: [Package]
  }
  deriving stock (Eq, Show)

-- | nvdが見出しで分ける変化の種類。
data SectionKind
  = VersionChanges
  | SelectionStateChanges
  | AddedPackages
  | RemovedPackages
  deriving stock (Bounded, Enum, Eq, Show)

-- | 一覧の1行。
data Package = Package
  { install :: InstallState
  , selection :: Maybe SelectionState
  -- ^ 選ばれているかの状態。nvdが選択の集合を持たない時は無い。
  , name :: Text
  , before :: [Version]
  -- ^ 追加や削除の一覧では、その唯一の側のバージョン。
  , after :: Maybe [Version]
  -- ^ バージョンの変化の一覧でだけある。
  }
  deriving stock (Eq, Show)

-- | 閉包の中でどう変わったか。
data InstallState
  = Installed
  | Added
  | Removed
  | Upgraded
  | Downgraded
  | Changed
  deriving stock (Bounded, Enum, Eq, Show)

-- | nvdが状態の1文字目に使う文字。
installStateCode :: InstallState -> Char
installStateCode = \case
  Installed -> 'I'
  Added -> 'A'
  Removed -> 'R'
  Upgraded -> 'U'
  Downgraded -> 'D'
  Changed -> 'C'

-- | `environment.systemPackages`に選ばれているか。
data SelectionState
  = Selected
  | Unselected
  | NewlySelected
  | NewlyUnselected
  | LeftOnlySelected
  | LeftOnlyUnselected
  | RightOnlySelected
  | RightOnlyUnselected
  deriving stock (Bounded, Enum, Eq, Show)

-- | nvdが状態の2文字目に使う文字。
selectionStateCode :: SelectionState -> Char
selectionStateCode = \case
  Selected -> '*'
  Unselected -> '.'
  NewlySelected -> '+'
  NewlyUnselected -> '-'
  LeftOnlySelected -> 'L'
  LeftOnlyUnselected -> 'l'
  RightOnlySelected -> 'R'
  RightOnlyUnselected -> 'r'

-- | バージョンの表示1つ分。
data Version = Version
  { label :: Maybe Text
  -- ^ バージョンの文字列。store pathに数字が無いと`<none>`と出るので、その時は無い。
  , count :: Int
  -- ^ 同じバージョンが閉包に何回あるか。
  }
  deriving stock (Eq, Show)

-- | 末尾の閉包の大きさの行。
data ClosureSize = ClosureSize
  { before :: Int
  , after :: Int
  , added :: Int
  , removed :: Int
  , diskUsage :: Maybe Text
  -- ^ ディスク使用量の差。nvdが`nix path-info`で求められなかった時は無い。
  }
  deriving stock (Eq, Show)

-- | 出力を読めなかった理由。megaparsecの説明をそのまま持つ。
newtype ReportFailure = Unparsable Text
  deriving stock (Eq, Show)

instance Exception ReportFailure where
  displayException (Unparsable detail) = "nvdの出力を読めませんでした:\n" <> convert detail

type Parser = Parsec Void Text

-- | `nvd diff`の標準出力の全体を読む。
parseReport :: Text -> Either ReportFailure Report
parseReport = over _Left (Unparsable . convert . errorBundlePretty) . runParser report "nvd diff"

report :: Parser Report
report =
  Report
    <$> (string "<<< " *> restOfLine)
    <*> (string ">>> " *> restOfLine)
    <*> (some section <|> [] <$ (string "No version or selection state changes." <* eol))
    <*> closureSize
    <* optional eol
    <* eof

restOfLine :: Parser Text
restOfLine = takeWhile1P (Just "store path") (/= '\n') <* eol

section :: Parser Section
section =
  Section
    <$> (choice [kind <$ string (sectionLabel kind) | kind <- [minBound .. maxBound]] <* eol)
    <*> some package

sectionLabel :: SectionKind -> Text
sectionLabel = \case
  VersionChanges -> "Version changes:"
  SelectionStateChanges -> "Selection state changes:"
  AddedPackages -> "Added packages:"
  RemovedPackages -> "Removed packages:"

package :: Parser Package
package =
  Package
    <$> (char '[' *> codeOf installStateCode)
    <*> (optional (codeOf selectionStateCode) <* char ']' <* hspace1 <* serial <* hspace1)
    <*> (takeWhile1P (Just "package name") (\c -> c /= ' ' && c /= '\n') <* hspace1)
    <*> versions
    <*> (optional (string " -> " *> versions) <* eol)
 where
  -- 通し番号は表示のためだけのものなので捨てる。
  serial = char '#' *> some digitChar

-- | 文字との対応表を逆に引いて状態を読む。
codeOf :: (Bounded a, Enum a) => (a -> Char) -> Parser a
codeOf code = choice [candidate <$ char (code candidate) | candidate <- [minBound .. maxBound]]

versions :: Parser [Version]
versions = [] <$ string "<no versions>" <|> version `sepBy1` string ", "

version :: Parser Version
version =
  Version . labelOf
    <$> takeWhile1P (Just "version") (\c -> c /= ' ' && c /= ',' && c /= '\n')
    <*> option 1 (string " x" *> decimal)
 where
  labelOf raw = if raw == "<none>" then Nothing else Just raw

closureSize :: Parser ClosureSize
closureSize =
  ClosureSize
    <$> (string "Closure size: " *> decimal)
    <*> (string " -> " *> decimal)
    <*> (string " (" *> decimal <* string " paths added, ")
    <*> (decimal <* string " paths removed, delta " <* delta)
    <*> (optional diskUsage <* string ").")
 where
  -- 差は追加と削除から求まるので読み飛ばす。
  delta = signed (pure ()) (decimal :: Parser Int)
  diskUsage = string ", disk usage " *> takeWhile1P (Just "disk usage") (/= ')')
