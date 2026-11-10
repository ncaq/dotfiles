-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import Himari
import NixGcRootHosts.Config (Config (..), configFrom)
import NixGcRootHosts.Failure (ConfigFailure (..))
import Test.Sandwich

-- | 連想リストを、環境変数を引く関数にする。
variables :: [(Text, Text)] -> Text -> Maybe Text
variables = flip lookup

tests :: TopSpec
tests = describe "configFrom" do
  it "flakeの指定が無ければデプロイ時に配置されるflakeを使う" do
    configFrom (variables [("STATE_DIRECTORY", "/var/lib/nix-gc-root-hosts")])
      `shouldBe` Right
        Config{stateDirectory = "/var/lib/nix-gc-root-hosts", flake = "/etc/nixos-flake"}
  it "flakeの指定があればそれを使う" do
    configFrom
      ( variables
          [ ("STATE_DIRECTORY", "/var/lib/nix-gc-root-hosts")
          , ("NIX_GC_ROOT_HOSTS_FLAKE", "github:ncaq/dotfiles")
          ]
      )
      `shouldBe` Right
        Config{stateDirectory = "/var/lib/nix-gc-root-hosts", flake = "github:ncaq/dotfiles"}
  it "状態ディレクトリが無ければ失敗にする" do
    configFrom (variables []) `shouldBe` Left (MissingVariable "STATE_DIRECTORY")
  it "状態ディレクトリが空でも失敗にする" do
    -- 空のまま進むと、カレントディレクトリの中身を古いrootとして消しに行く。
    configFrom (variables [("STATE_DIRECTORY", "")])
      `shouldBe` Left (MissingVariable "STATE_DIRECTORY")
