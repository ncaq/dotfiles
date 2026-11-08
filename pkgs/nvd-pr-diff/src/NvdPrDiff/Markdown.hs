-- | 読んだ差分をPRコメントのMarkdownにする。
--
-- 先頭に目印のコメントを置き、同じPRで次に走った時に自分のコメントを見つけて書き換える。
-- 見出しはnvdの区分をそのまま使い、各区分は表にする。
-- `nixos-system-*`はdotfilesの更新で必ず変わるノイズなので載せない。
module NvdPrDiff.Markdown
  ( marker
  , render
  ) where

import Data.Text (intercalate, isInfixOf)
import Himari
import NvdPrDiff.Report

-- | コメントの先頭に置く目印。
marker :: Text
marker = "<!-- nvd-pr-diff -->"

-- | ホスト名とベースブランチ名を添えて、コメントの本文を組み立てる。
render :: Text -> Text -> Report -> Text
render host baseRef report =
  intercalate "\n" $
    [marker, "## nvd diff: " <> host <> " (base: " <> baseRef <> ")", ""]
      <> ( if null sections
             then ["No version or selection state changes.", ""]
             else concatMap renderSection sections
         )
      <> [renderClosure report.closure, ""]
 where
  sections = filter (not . null . (.packages)) (fmap dropNoise report.sections)
  dropNoise section = section{packages = filter (not . isSystem) section.packages}
  isSystem package = "nixos-system-" `isInfixOf` package.name

renderSection :: Section -> [Text]
renderSection section =
  ["### " <> title section.kind, "", "| State | Package | Version |", "| --- | --- | --- |"]
    <> fmap renderPackage section.packages
    <> [""]

title :: SectionKind -> Text
title = \case
  VersionChanges -> "Version changes"
  SelectionStateChanges -> "Selection state changes"
  AddedPackages -> "Added packages"
  RemovedPackages -> "Removed packages"

renderPackage :: Package -> Text
renderPackage package =
  "| `" <> status <> "` | `" <> package.name <> "` | " <> versions <> " |"
 where
  status =
    convert
      (installStateCode package.install : foldMap (pure . selectionStateCode) package.selection)
  versions = renderVersions package.before <> foldMap ((" -> " <>) . renderVersions) package.after

renderVersions :: [Version] -> Text
renderVersions [] = "`<no versions>`"
renderVersions versions = "`" <> intercalate ", " (fmap renderVersion versions) <> "`"

renderVersion :: Version -> Text
renderVersion version =
  fromMaybe "<none>" version.label
    <> if version.count == 1 then "" else " x" <> number version.count

renderClosure :: ClosureSize -> Text
renderClosure closure =
  mconcat
    [ "Closure size: "
    , number closure.before
    , " -> "
    , number closure.after
    , " ("
    , number closure.added
    , " paths added, "
    , number closure.removed
    , " paths removed, delta "
    , signedNumber (closure.added - closure.removed)
    , foldMap (", disk usage " <>) closure.diskUsage
    , ")."
    ]

number :: Int -> Text
number = convert . show

-- | nvdの`%+d`と同じく、負でなければ`+`を付ける。
signedNumber :: Int -> Text
signedNumber n = (if n < 0 then "" else "+") <> number n
