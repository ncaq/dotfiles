-- | 環境変数からの投稿先の組み立てのテスト。
module Spec.TargetSpec (tests) where

import Himari
import NvdPrDiff.Target
import Test.Sandwich

environment :: [(Text, Text)]
environment =
  [ ("BASE_REF", "master")
  , ("PR_NUMBER", "1234")
  , ("GITHUB_REPOSITORY", "ncaq/dotfiles")
  , ("GH_TOKEN", "ghs_secret")
  ]

targetWith :: [(Text, Text)] -> Either TargetFailure Target
targetWith table = targetFrom (`lookup` table)

tests :: TopSpec
tests = describe "targetFrom" do
  it "4つの環境変数から組み立てる" do
    targetWith environment
      `shouldBe` Right
        Target
          { baseRef = "master"
          , prNumber = 1234
          , repository = "ncaq/dotfiles"
          , token = Token "ghs_secret"
          }
  it "トークンはshowしても中身を出さない" do
    show (Token "ghs_secret") `shouldBe` "Token <redacted>"
  for_ ["BASE_REF", "PR_NUMBER", "GITHUB_REPOSITORY", "GH_TOKEN"] \name ->
    it (convert name <> "が無ければその名前を報告する") do
      targetWith (filter ((/= name) . fst) environment) `shouldBe` Left (MissingVariable name)
  -- GitHub Actionsは`${{ github.base_ref }}`のように値が無い式を空文字列で渡すので、
  -- 空は無いのと同じに扱う。消したBash版の`${VAR:?}`も空を弾いていた。
  for_ ["BASE_REF", "PR_NUMBER", "GITHUB_REPOSITORY", "GH_TOKEN"] \name ->
    it (convert name <> "が空文字列でもその名前を報告する") do
      targetWith ((name, "") : environment) `shouldBe` Left (MissingVariable name)
  it "PR番号が数でなければ生の値を報告する" do
    targetWith (("PR_NUMBER", "abc") : environment) `shouldBe` Left (InvalidPrNumber "abc")
