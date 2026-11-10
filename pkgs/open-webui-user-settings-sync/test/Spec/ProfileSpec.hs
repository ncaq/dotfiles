-- | プロフィールの宣言と、実体との比べ方のテスト。
module Spec.ProfileSpec (tests) where

import Fixture
import Himari
import Test.Sandwich
import UserSettingsSync.Profile (declaredColumns, desiredProfile)

declared :: Map Text Value
declared = fields [aesonQQ|{"name": "エヌユル", "gender": "male"}|]

desired :: Map Text Value
desired = desiredProfile declared "RIFF"

tests :: TopSpec
tests = do
  describe "desiredProfile" do
    it "宣言した列に、画像をdata URLにして足す" do
      desired
        `shouldBe` fields
          [aesonQQ|{
            "name": "エヌユル",
            "gender": "male",
            "profile_image_url": "data:image/webp;base64,UklGRg=="
          }|]
  describe "declaredColumns" do
    it "応答から宣言した列だけを取り出す" do
      declaredColumns
        desired
        [aesonQQ|{
          "name": "エヌユル",
          "gender": "male",
          "profile_image_url": "data:image/webp;base64,UklGRg==",
          "email": "admin@localhost",
          "role": "admin"
        }|]
        `shouldBe` desired
    it "応答に無い列はnullとして取り出す" do
      declaredColumns desired [aesonQQ|{"name": "User", "email": "admin@localhost"}|]
        `shouldBe` fields [aesonQQ|{"name": "User", "gender": null, "profile_image_url": null}|]
    it "応答がオブジェクトでなければ、全ての列をnullとして取り出す" do
      declaredColumns desired Null
        `shouldBe` fields [aesonQQ|{"name": null, "gender": null, "profile_image_url": null}|]
