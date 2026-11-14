-- | 集めた事実から環境の種類を決めるテスト。
module Spec.PlatformSpec (tests) where

import DotfilesInstall.Architecture (Architecture (..))
import DotfilesInstall.Failure (UnsupportedArchitecture (..))
import DotfilesInstall.Platform
import DotfilesInstall.Probe (Probe (..))
import Himari
import Test.Sandwich

-- | NixOSでもTermuxでもないx86_64のLinux。
plain :: Probe
plain = Probe{isNixos = False, isTermux = False, hostName = "bullet", machineName = "x86_64"}

tests :: TopSpec
tests = describe "detectPlatform" do
  it "/etc/NIXOSがあればホスト名付きのNixOSにする" do
    detectPlatform plain{isNixos = True} `shouldBe` Right (NixOS "bullet")
  it "TermuxならNix-on-Droidにする" do
    detectPlatform plain{isTermux = True, machineName = "aarch64"} `shouldBe` Right NixOnDroid
  it "両方に当てはまる時はNixOSを優先する" do
    detectPlatform plain{isNixos = True, isTermux = True} `shouldBe` Right (NixOS "bullet")
  it "どちらでもないx86_64はhome-managerにする" do
    detectPlatform plain `shouldBe` Right (HomeManager X86_64)
  it "どちらでもないaarch64はhome-managerにする" do
    detectPlatform plain{machineName = "aarch64"} `shouldBe` Right (HomeManager Aarch64)
  it "どちらでもない未対応のアーキテクチャは失敗にする" do
    detectPlatform plain{machineName = "riscv64"}
      `shouldBe` Left (UnsupportedArchitecture "riscv64")
  it "NixOSでは未対応のアーキテクチャでも失敗にしない" do
    detectPlatform plain{isNixos = True, machineName = "riscv64"} `shouldBe` Right (NixOS "bullet")
