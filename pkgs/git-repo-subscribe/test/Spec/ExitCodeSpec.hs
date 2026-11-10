-- | 失敗したGitの終了コードの扱いのテスト。
module Spec.ExitCodeSpec (tests) where

import GitRepoSubscribe.ExitCode
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "gitExitCode" do
  for_ [1, 128, 255] \code ->
    it (show code <> "はそのまま返す") do
      gitExitCode (ExitFailure code) `shouldBe` ExitFailure code
  -- 256以上は終了コードとして表せず、負の値はシグナルで止まったことを表す。
  for_ [256, -9, 0] \code ->
    it (show code <> "は1にする") do
      gitExitCode (ExitFailure code) `shouldBe` ExitFailure 1
  it "失敗の報告なのに成功を表していたら1にする" do
    gitExitCode ExitSuccess `shouldBe` ExitFailure 1
