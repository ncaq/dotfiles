-- | `nvd diff`の出力の読み取りのテスト。
--
-- 実際の出力はnvdの`print_packages`の形に倣って組み立てる。
-- 状態の記号、通し番号の桁揃え、名前の幅揃え、複数のバージョン、`<none>`を1つの出力に詰めて、
-- 行のどの部分の読み違いも位置ではなく値の違いとして出るようにする。
module Spec.ReportSpec (tests) where

import Data.Text (intercalate)
import Himari
import NvdPrDiff.Report
import Test.Sandwich

beforePath :: Text
beforePath = "/nix/store/0000000000000000000000000000000a-nixos-system-seminar-26.05.1"

afterPath :: Text
afterPath = "/nix/store/0000000000000000000000000000000b-nixos-system-seminar-26.05.2"

header :: [Text]
header = ["<<< " <> beforePath, ">>> " <> afterPath]

closureLine :: Text
closureLine =
  "Closure size: 1234 -> 1240 (10 paths added, 4 paths removed, delta +6, disk usage +1.2 MiB)."

-- | パッケージが減った時の閉包の行。差もディスク使用量も負になる。
shrinkingClosureLine :: Text
shrinkingClosureLine =
  "Closure size: 10 -> 8 (1 paths added, 3 paths removed, delta -2, disk usage -1.2 MiB)."

closure :: ClosureSize
closure =
  ClosureSize{before = 1234, after = 1240, added = 10, removed = 4, diskUsage = Just "+1.2 MiB"}

-- | 全ての区分を含む出力。
full :: Text
full =
  intercalate "\n" $
    header
      <> [ "Version changes:"
         , "[U.]  #01  foo                   1.0 -> 1.1"
         , "[D*]  #02  bar-baz               2.0, 2.1 x2 -> 1.9"
         , "[C.]  #03  nixos-system-seminar  26.05.20261101.aaaaaaa -> 26.05.20261108.bbbbbbb"
         , "Selection state changes:"
         , "[C+]  #1  qux  <none>"
         , "Added packages:"
         , "[A.]  #1  new-pkg  0.1"
         , "Removed packages:"
         , "[R.]  #1  old-pkg  <none> x2"
         , closureLine
         , ""
         ]

single :: Text -> Version
single raw = Version{label = Just raw, count = 1}

tests :: TopSpec
tests = describe "parseReport" do
  it "全ての区分と状態を読む" do
    parseReport full
      `shouldBe` Right
        Report
          { before = beforePath
          , after = afterPath
          , sections =
              [ Section
                  { kind = VersionChanges
                  , packages =
                      [ Package
                          { install = Upgraded
                          , selection = Just Unselected
                          , name = "foo"
                          , before = [single "1.0"]
                          , after = Just [single "1.1"]
                          }
                      , Package
                          { install = Downgraded
                          , selection = Just Selected
                          , name = "bar-baz"
                          , before = [single "2.0", Version{label = Just "2.1", count = 2}]
                          , after = Just [single "1.9"]
                          }
                      , Package
                          { install = Changed
                          , selection = Just Unselected
                          , name = "nixos-system-seminar"
                          , before = [single "26.05.20261101.aaaaaaa"]
                          , after = Just [single "26.05.20261108.bbbbbbb"]
                          }
                      ]
                  }
              , Section
                  { kind = SelectionStateChanges
                  , packages =
                      [ Package
                          { install = Changed
                          , selection = Just NewlySelected
                          , name = "qux"
                          , before = [Version{label = Nothing, count = 1}]
                          , after = Nothing
                          }
                      ]
                  }
              , Section
                  { kind = AddedPackages
                  , packages =
                      [ Package
                          { install = Added
                          , selection = Just Unselected
                          , name = "new-pkg"
                          , before = [single "0.1"]
                          , after = Nothing
                          }
                      ]
                  }
              , Section
                  { kind = RemovedPackages
                  , packages =
                      [ Package
                          { install = Removed
                          , selection = Just Unselected
                          , name = "old-pkg"
                          , before = [Version{label = Nothing, count = 2}]
                          , after = Nothing
                          }
                      ]
                  }
              ]
          , closure
          }
  it "変化が無い出力は区分が空になる" do
    parseReport
      ( intercalate
          "\n"
          ( header
              <> [ "No version or selection state changes."
                 , "Closure size: 10 -> 10 (0 paths added, 0 paths removed, delta +0)."
                 ]
          )
      )
      `shouldBe` Right
        Report
          { before = beforePath
          , after = afterPath
          , sections = []
          , closure =
              ClosureSize{before = 10, after = 10, added = 0, removed = 0, diskUsage = Nothing}
          }
  -- パッケージを減らすPRでは差もディスク使用量も負になる。
  it "減った差と負のディスク使用量を読む" do
    parseReport
      ( intercalate
          "\n"
          (header <> ["No version or selection state changes.", shrinkingClosureLine])
      )
      `shouldBe` Right
        Report
          { before = beforePath
          , after = afterPath
          , sections = []
          , closure =
              ClosureSize
                { before = 10
                , after = 8
                , added = 1
                , removed = 3
                , diskUsage = Just "-1.2 MiB"
                }
          }
  it "選択の記号が無い行も読む" do
    parseReport
      (intercalate "\n" (header <> ["Added packages:", "[A]  #1  new-pkg  0.1", closureLine]))
      `shouldBe` Right
        Report
          { before = beforePath
          , after = afterPath
          , sections =
              [ Section
                  { kind = AddedPackages
                  , packages =
                      [ Package
                          { install = Added
                          , selection = Nothing
                          , name = "new-pkg"
                          , before = [single "0.1"]
                          , after = Nothing
                          }
                      ]
                  }
              ]
          , closure
          }
  it "形が違えば何を待っていたかを添えて失敗する" do
    case parseReport "garbage" of
      Left (Unparsable detail) -> detail `textShouldContain` "<<< "
      Right parsed -> expectationFailure ("読めてしまいました: " <> show parsed)
