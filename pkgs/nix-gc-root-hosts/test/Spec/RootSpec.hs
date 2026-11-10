-- | rootの名前とinstallableの組み立てのテスト。
module Spec.RootSpec (tests) where

import NixGcRootHosts.Root (Root (..), homeRoot, nixosRoot)
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "nixosRoot" do
    it "ホストのtoplevelを指す" do
      nixosRoot "/etc/nixos-flake" "bullet"
        `shouldBe` Root
          { name = "nixos-bullet"
          , installable =
              "/etc/nixos-flake#nixosConfigurations.bullet.config.system.build.toplevel"
          }
  describe "homeRoot" do
    it "システムのhome-managerの閉包を指す" do
      homeRoot "/etc/nixos-flake" "x86_64-linux"
        `shouldBe` Root
          { name = "home-manager-x86_64-linux"
          , installable = "/etc/nixos-flake#homeConfigurations.x86_64-linux.activationPackage"
          }
