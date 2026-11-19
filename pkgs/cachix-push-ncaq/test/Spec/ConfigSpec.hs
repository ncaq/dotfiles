-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import CachixPushNcaq.Config (Config (..), configFrom)
import CachixPushNcaq.Failure (ConfigFailure (..))
import Himari
import Test.Sandwich

-- | 連想リストを、環境変数を引く関数にする。
variables :: [(Text, Text)] -> Text -> Maybe Text
variables = flip lookup

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
