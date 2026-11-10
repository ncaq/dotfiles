-- | 状態ディレクトリから消すものの決定のテスト。
--
-- ここを誤ると、守っているはずの閉包がGCで消える。
module Spec.StaleSpec (tests) where

import NixGcRootHosts.Stale (staleEntries)
import Test.Sandwich

tests :: TopSpec
tests = describe "staleEntries" do
  it "今の構成に無い名前だけを返す" do
    staleEntries ["nixos-bullet", "nixos-seminar"] ["nixos-bullet", "nixos-old", "nixos-seminar"]
      `shouldBe` ["nixos-old"]
  it "全て今の構成にあれば何も返さない" do
    staleEntries
      ["nixos-bullet", "home-manager-x86_64-linux"]
      ["home-manager-x86_64-linux", "nixos-bullet"]
      `shouldBe` []
  it "まだ張られていないrootがあっても何も返さない" do
    staleEntries ["nixos-bullet", "nixos-seminar"] ["nixos-bullet"] `shouldBe` []
  it "名前が前方一致するだけのものは別物として返す" do
    staleEntries ["nixos-bullet"] ["nixos-bullet2", "nixos"] `shouldBe` ["nixos-bullet2", "nixos"]
  it "状態ディレクトリが空なら何も返さない" do
    staleEntries ["nixos-bullet"] [] `shouldBe` []
