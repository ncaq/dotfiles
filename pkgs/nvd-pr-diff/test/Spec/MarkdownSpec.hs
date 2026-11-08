-- | コメントの本文の組み立てのテスト。
module Spec.MarkdownSpec (tests) where

import Data.Text (intercalate)
import Himari
import NvdPrDiff.Markdown
import NvdPrDiff.Report
import Test.Sandwich

closure :: ClosureSize
closure =
  ClosureSize{before = 1234, after = 1240, added = 10, removed = 4, diskUsage = Just "+1.2 MiB"}

-- | `closure`をnvdの形で書いたもの。
closureLine :: Text
closureLine =
  "Closure size: 1234 -> 1240 (10 paths added, 4 paths removed, delta +6, disk usage +1.2 MiB)."

report :: [Section] -> Report
report sections = Report{before = "/nix/store/a", after = "/nix/store/b", sections, closure}

single :: Text -> Version
single raw = Version{label = Just raw, count = 1}

upgraded :: Package
upgraded =
  Package
    { install = Upgraded
    , selection = Just Unselected
    , name = "foo"
    , before = [single "1.0"]
    , after = Just [single "1.1", Version{label = Just "1.2", count = 2}]
    }

-- | 変化前のバージョンの一覧が空のパッケージ。
bare :: Package
bare =
  Package
    { install = Changed
    , selection = Just Unselected
    , name = "bare"
    , before = []
    , after = Just [single "1.0"]
    }

system :: Package
system =
  Package
    { install = Changed
    , selection = Just Unselected
    , name = "nixos-system-seminar"
    , before = [single "26.05.1"]
    , after = Just [single "26.05.2"]
    }

tests :: TopSpec
tests = describe "render" do
  it "目印と見出しと表と閉包の行を並べる" do
    render
      "seminar"
      "master"
      ( report
          [ Section{kind = VersionChanges, packages = [upgraded, bare]}
          , Section
              { kind = RemovedPackages
              , packages =
                  [ Package
                      { install = Removed
                      , selection = Nothing
                      , name = "old-pkg"
                      , before = [Version{label = Nothing, count = 1}]
                      , after = Nothing
                      }
                  ]
              }
          ]
      )
      `shouldBe` intercalate
        "\n"
        [ marker
        , "## nvd diff: seminar (base: master)"
        , ""
        , "### Version changes"
        , ""
        , "| State | Package | Version |"
        , "| --- | --- | --- |"
        , "| `U.` | `foo` | `1.0` -> `1.1, 1.2 x2` |"
        , "| `C.` | `bare` | `<no versions>` -> `1.0` |"
        , ""
        , "### Removed packages"
        , ""
        , "| State | Package | Version |"
        , "| --- | --- | --- |"
        , "| `R` | `old-pkg` | `<none>` |"
        , ""
        , closureLine
        , ""
        ]
  it "nixos-systemは載せず、空になった区分は見出しごと省く" do
    render
      "seminar"
      "master"
      ( report
          [ Section{kind = VersionChanges, packages = [system]}
          , Section{kind = AddedPackages, packages = [upgraded{install = Added, after = Nothing}]}
          ]
      )
      `shouldBe` intercalate
        "\n"
        [ marker
        , "## nvd diff: seminar (base: master)"
        , ""
        , "### Added packages"
        , ""
        , "| State | Package | Version |"
        , "| --- | --- | --- |"
        , "| `A.` | `foo` | `1.0` |"
        , ""
        , closureLine
        , ""
        ]
  it "何も残らなければ変化が無いと書く" do
    render "seminar" "master" (report [Section{kind = VersionChanges, packages = [system]}])
      `shouldBe` intercalate
        "\n"
        [ marker
        , "## nvd diff: seminar (base: master)"
        , ""
        , "No version or selection state changes."
        , ""
        , closureLine
        , ""
        ]
  it "ディスク使用量が無ければ省き、減った差は負の数で書く" do
    render
      "seminar"
      "master"
      (report [])
        { closure = ClosureSize{before = 10, after = 8, added = 1, removed = 3, diskUsage = Nothing}
        }
      `shouldBe` intercalate
        "\n"
        [ marker
        , "## nvd diff: seminar (base: master)"
        , ""
        , "No version or selection state changes."
        , ""
        , "Closure size: 10 -> 8 (1 paths added, 3 paths removed, delta -2)."
        , ""
        ]
