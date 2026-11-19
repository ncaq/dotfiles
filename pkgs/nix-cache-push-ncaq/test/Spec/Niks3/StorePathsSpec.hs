-- | 標準入力のstoreパスの一覧の読み方のテスト。
module Spec.Niks3.StorePathsSpec (tests) where

import NixCachePushNcaq.Niks3.StorePaths (storePathsFrom)
import Test.Sandwich

tests :: TopSpec
tests = describe "storePathsFrom" do
  it "1行に1つずつ読む" do
    storePathsFrom "/nix/store/a\n/nix/store/b\n" `shouldBe` ["/nix/store/a", "/nix/store/b"]
  it "末尾の改行が無くても読む" do
    storePathsFrom "/nix/store/a\n/nix/store/b" `shouldBe` ["/nix/store/a", "/nix/store/b"]
  it "空の行は捨てる" do
    storePathsFrom "/nix/store/a\n\n/nix/store/b\n\n" `shouldBe` ["/nix/store/a", "/nix/store/b"]
  it "空の入力は空の一覧にする" do
    storePathsFrom "" `shouldBe` []
