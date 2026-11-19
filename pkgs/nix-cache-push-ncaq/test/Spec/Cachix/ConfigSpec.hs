-- | `cachix-push-ncaq`の設定の環境変数の読み方のテスト。
module Spec.Cachix.ConfigSpec (tests) where

import Fixture (variables)
import Himari
import NixCachePushNcaq.Cachix.Config (Config (..), configFrom)
import NixCachePushNcaq.Failure (ConfigFailure (..))
import Test.Sandwich

tests :: TopSpec
tests = describe "configFrom" do
  it "指定が無ければホームのdotfilesのシークレットとncaqのキャッシュを使う" do
    configFrom (variables [("HOME", "/home/ncaq")])
      >>= ( `shouldBe`
              Config{secretsFile = "/home/ncaq/dotfiles/secrets/cachix.yaml", cacheName = "ncaq"}
          )
  it "シークレットファイルとキャッシュの指定があればそれを使う" do
    configFrom
      ( variables
          [ ("HOME", "/home/ncaq")
          , ("CACHIX_PUSH_NCAQ_SECRETS_FILE", "/tmp/cachix.yaml")
          , ("CACHIX_PUSH_NCAQ_CACHE", "other")
          ]
      )
      >>= (`shouldBe` Config{secretsFile = "/tmp/cachix.yaml", cacheName = "other"})
  it "空の指定は無いのと同じに扱う" do
    configFrom
      ( variables
          [ ("HOME", "/home/ncaq")
          , ("CACHIX_PUSH_NCAQ_SECRETS_FILE", "")
          , ("CACHIX_PUSH_NCAQ_CACHE", "")
          ]
      )
      >>= ( `shouldBe`
              Config{secretsFile = "/home/ncaq/dotfiles/secrets/cachix.yaml", cacheName = "ncaq"}
          )
  it "シークレットファイルの指定があればHOMEは要らない" do
    configFrom (variables [("CACHIX_PUSH_NCAQ_SECRETS_FILE", "/tmp/cachix.yaml")])
      >>= (`shouldBe` Config{secretsFile = "/tmp/cachix.yaml", cacheName = "ncaq"})
  it "シークレットファイルの指定もHOMEも無ければ失敗にする" do
    configFrom (variables []) `shouldThrow` (== MissingVariable "HOME")
