-- | 宣言のファイルの読み込みのテスト。
module Spec.DeclaredSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import Himari
import Test.Sandwich
import UserSettingsSync.Config (Config (..))
import UserSettingsSync.Declared (readDeclaration)
import UserSettingsSync.Failure (DeclarationFailure (..))
import UserSettingsSync.Sync (Declaration (..))

-- | 宣言の4つのファイルの中身。
data Files = Files
  { settingsJson :: ByteString
  , promptText :: ByteString
  , profileJson :: ByteString
  , imageBytes :: ByteString
  }

-- | どれも読める中身。
valid :: Files
valid =
  Files
    { settingsJson = "{\"ctrlEnterToSend\": true}"
    , promptText = convert ("日本語で答えてください。\n" :: Text)
    , -- `ByteString`のリテラルは1文字を1バイトへ切り詰めるので、`Text`から変換する。
      profileJson = convert ("{\"name\": \"エヌユル\"}" :: Text)
    , -- UTF-8として読めないバイトを含める。
      imageBytes = "RIFF\0\255\254WEBP"
    }

-- | 中身を一時ディレクトリへ書いて、それを指す設定を渡す。
withFiles :: (MonadUnliftIO m) => Files -> (Config -> m a) -> m a
withFiles files action =
  withSystemTempDirectory "open-webui-user-settings-sync-test" \directory -> do
    let config =
          Config
            { url = "http://localhost"
            , declaredSettingsFile = directory </> "settings.json"
            , systemPromptFile = directory </> "prompt.md"
            , declaredProfileFile = directory </> "profile.json"
            , profileImageFile = directory </> "favicon.webp"
            }
    liftIO do
      B.writeFile config.declaredSettingsFile files.settingsJson
      B.writeFile config.systemPromptFile files.promptText
      B.writeFile config.declaredProfileFile files.profileJson
      B.writeFile config.profileImageFile files.imageBytes
    action config

tests :: TopSpec
tests = describe "readDeclaration" do
  it "4つのファイルを読んで宣言にする" do
    declaration <- withFiles valid readDeclaration
    declaration
      `shouldBe` Declaration
        { settings = fields [aesonQQ|{"ctrlEnterToSend": true}|]
        , systemPrompt = "日本語で答えてください。\n"
        , profile = fields [aesonQQ|{"name": "エヌユル"}|]
        , profileImage = "RIFF\0\255\254WEBP"
        }
  for_ undecodable \(shape, content) -> do
    it ("設定の宣言が" <> shape <> "なら、そのパスを持つ失敗にする") do
      withFiles valid{settingsJson = content} \config ->
        readDeclaration config `shouldThrow` \case
          UndecodableDeclaration path _ -> path == config.declaredSettingsFile
    it ("プロフィールの宣言が" <> shape <> "なら、そのパスを持つ失敗にする") do
      withFiles valid{profileJson = content} \config ->
        readDeclaration config `shouldThrow` \case
          UndecodableDeclaration path _ -> path == config.declaredProfileFile
 where
  undecodable :: [(String, ByteString)]
  undecodable =
    [ ("JSONとして壊れている", "{\"name\": ")
    , ("配列", "[]")
    , ("null", "null")
    , ("空", "")
    ]
