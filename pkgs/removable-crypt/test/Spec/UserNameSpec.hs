-- | コマンドを呼んだ人の決め方のテスト。
module Spec.UserNameSpec (tests) where

import Himari
import RemovableCrypt.UserName (invokingUser)
import Test.Sandwich

tests :: TopSpec
tests = describe "invokingUser" do
  it "sudo越しなら、sudoを呼んだ人にする" do
    invokingUser (`lookup` [("SUDO_USER", "ncaq"), ("USER", "root")]) `shouldBe` Just "ncaq"
  it "sudo越しでなければ、今のユーザにする" do
    invokingUser (`lookup` [("USER", "ncaq")]) `shouldBe` Just "ncaq"
  it "SUDO_USERが空なら、今のユーザにする" do
    invokingUser (`lookup` [("SUDO_USER", ""), ("USER", "root")]) `shouldBe` Just "root"
  it "どちらも無ければ決められない" do
    invokingUser (const Nothing) `shouldBe` Nothing
