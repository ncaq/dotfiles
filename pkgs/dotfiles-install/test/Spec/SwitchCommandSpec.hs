-- | 環境の種類ごとの適用のコマンドのテスト。
module Spec.SwitchCommandSpec (tests) where

import DotfilesInstall.Architecture (Architecture (..))
import DotfilesInstall.Platform (Platform (..))
import DotfilesInstall.SwitchCommand
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "switchCommand" do
    it "NixOSではホスト名の構成をsudo付きのnixos-rebuildで適用する" do
      switchCommand (NixOS "bullet")
        `shouldBe` SwitchCommand "sudo" ["nixos-rebuild", "switch", "--flake", ".#bullet"]
    it "Nix-on-Droidではnix-on-droidで適用する" do
      switchCommand NixOnDroid `shouldBe` SwitchCommand "nix-on-droid" ["switch", "--flake", "."]
    it "x86_64のhome-managerではバックアップの拡張子を付けて適用する" do
      switchCommand (HomeManager X86_64)
        `shouldBe` SwitchCommand
          "home-manager"
          ["--flake", ".#x86_64-linux", "-b", "hm-bak", "switch"]
    it "aarch64のhome-managerではaarch64の構成を指す" do
      switchCommand (HomeManager Aarch64)
        `shouldBe` SwitchCommand
          "home-manager"
          ["--flake", ".#aarch64-linux", "-b", "hm-bak", "switch"]
  describe "commandLine" do
    it "プログラムと引数を空白で繋ぐ" do
      commandLine (switchCommand NixOnDroid) `shouldBe` "nix-on-droid switch --flake ."
