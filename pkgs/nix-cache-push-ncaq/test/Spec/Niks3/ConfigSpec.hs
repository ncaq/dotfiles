-- | `niks3-push-ncaq`の設定の環境変数の読み方のテスト。
module Spec.Niks3.ConfigSpec (tests) where

import Fixture (variables)
import Himari
import NixCachePushNcaq.Failure (ConfigFailure (..))
import NixCachePushNcaq.Niks3.Config (Config (..), configFrom)
import Test.Sandwich

tests :: TopSpec
tests = describe "configFrom" do
  it "シークレットファイルとサーバのURLと一時ファイルの置き場所を読む" do
    configFrom
      ( variables
          [ ("NIKS3_PUSH_NCAQ_SECRETS_FILE", "/tmp/niks3.yaml")
          , ("NIKS3_PUSH_NCAQ_SERVER_URL", "https://niks3.example.com/")
          , ("XDG_RUNTIME_DIR", "/run/user/1000")
          ]
      )
      >>= ( `shouldBe`
              Config
                { secretsFile = "/tmp/niks3.yaml"
                , serverUrl = "https://niks3.example.com/"
                , runtimeDirectory = Just "/run/user/1000"
                }
          )
  it "XDG_RUNTIME_DIRが無くても空でも読む" do
    let expected =
          Config
            { secretsFile = "/tmp/niks3.yaml"
            , serverUrl = "https://niks3.example.com/"
            , runtimeDirectory = Nothing
            }
        required =
          [ ("NIKS3_PUSH_NCAQ_SECRETS_FILE", "/tmp/niks3.yaml")
          , ("NIKS3_PUSH_NCAQ_SERVER_URL", "https://niks3.example.com/")
          ]
    configFrom (variables required) >>= (`shouldBe` expected)
    configFrom (variables (("XDG_RUNTIME_DIR", "") : required)) >>= (`shouldBe` expected)
  it "シークレットファイルの指定が無ければ失敗にする" do
    configFrom (variables [("NIKS3_PUSH_NCAQ_SERVER_URL", "https://niks3.example.com/")])
      `shouldThrow` (== MissingVariable "NIKS3_PUSH_NCAQ_SECRETS_FILE")
  it "サーバのURLの指定が無ければ失敗にする" do
    configFrom (variables [("NIKS3_PUSH_NCAQ_SECRETS_FILE", "/tmp/niks3.yaml")])
      `shouldThrow` (== MissingVariable "NIKS3_PUSH_NCAQ_SERVER_URL")
  it "空の指定も失敗にする" do
    configFrom
      ( variables
          [ ("NIKS3_PUSH_NCAQ_SECRETS_FILE", "/tmp/niks3.yaml")
          , ("NIKS3_PUSH_NCAQ_SERVER_URL", "")
          ]
      )
      `shouldThrow` (== MissingVariable "NIKS3_PUSH_NCAQ_SERVER_URL")
