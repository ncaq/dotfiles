-- | Open WebUIへ送る内容のテスト。
module Spec.CallSpec (tests) where

import Fixture
import Himari
import Test.Sandwich
import UserSettingsSync.Call
import UserSettingsSync.Token (Token)

tests :: TopSpec
tests = describe "Call" do
  it "起動の確認にはトークンを付けない" do
    health `shouldBe` Call{method = Get, path = "/health", authorization = Nothing, body = Nothing}
  it "認証が無効なインスタンスの決まった資格情報でサインインする" do
    signIn
      `shouldBe` Call
        { method = Post
        , path = "/api/v1/auths/signin"
        , authorization = Nothing
        , body = Just [aesonQQ|{"email": "admin@localhost", "password": "admin"}|]
        }
  it "設定の取得にはトークンを付ける" do
    getSettings "token"
      `shouldBe` Call
        { method = Get
        , path = "/api/v1/users/user/settings"
        , authorization = Just "token"
        , body = Nothing
        }
  it "設定はuiの下へ包んで送る" do
    updateSettings "token" (fields [aesonQQ|{"ctrlEnterToSend": true}|])
      `shouldBe` Call
        { method = Post
        , path = "/api/v1/users/user/settings/update"
        , authorization = Just "token"
        , body = Just [aesonQQ|{"ui": {"ctrlEnterToSend": true}}|]
        }
  it "プロフィールの取得にはトークンを付ける" do
    getProfile "token"
      `shouldBe` Call
        { method = Get
        , path = "/api/v1/auths/"
        , authorization = Just "token"
        , body = Nothing
        }
  it "プロフィールは列をそのまま送る" do
    updateProfile "token" (fields [aesonQQ|{"name": "エヌユル"}|])
      `shouldBe` Call
        { method = Post
        , path = "/api/v1/auths/update/profile"
        , authorization = Just "token"
        , body = Just [aesonQQ|{"name": "エヌユル"}|]
        }
  it "トークンは表示しても中身を出さない" do
    show ("token" :: Token) `shouldBe` "Token <redacted>"
