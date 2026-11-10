-- | 設定とプロフィールの同期を通しで行うテスト。
--
-- Open WebUIは、設定とプロフィールをメモリに持って呼び出しを記録するだけの偽物に差し替える。
module Spec.SyncSpec (tests) where

import Fixture
import Himari
import Test.Sandwich
import UserSettingsSync.Call (Call (..), Method (..))
import UserSettingsSync.Failure (ApiFailure (..), SyncFailure (..))
import UserSettingsSync.Profile (desiredProfile)
import UserSettingsSync.Sync (Declaration (..), Environment (..), sync)

-- | 偽のOpen WebUIの状態と振る舞い。
data Server = Server
  { healthFailures :: Int
  -- ^ 起動の確認が、最初に何回失敗するか。
  , signInResponse :: Value
  , storedSettings :: Value
  , storedProfile :: Map Text Value
  , acceptedColumns :: [Text]
  -- ^ プロフィールの更新で受け付ける列。それ以外は黙って捨てる。
  }

declaration :: Declaration
declaration =
  Declaration
    { settings = fields [aesonQQ|{"ctrlEnterToSend": true}|]
    , systemPrompt = "こんにちは\n"
    , profile = fields [aesonQQ|{"name": "エヌユル"}|]
    , profileImage = "RIFF"
    }

-- | 宣言と一致している状態。
synced :: Server
synced =
  Server
    { healthFailures = 0
    , signInResponse = [aesonQQ|{"token": "token", "role": "admin"}|]
    , storedSettings = [aesonQQ|{"ui": {"ctrlEnterToSend": true, "system": "こんにちは"}}|]
    , storedProfile =
        desiredProfile declaration.profile declaration.profileImage
          <> fields [aesonQQ|{"email": "admin@localhost"}|]
    , acceptedColumns = ["name", "profile_image_url"]
    }

-- | 同期して、結果と、送った呼び出しの宛先と、同期した後のサーバの設定とプロフィールを返す。
synchronized
  :: (MonadUnliftIO m)
  => Server
  -> m (Either SomeException (), [(Method, Text)], Value, Map Text Value)
synchronized server = do
  calls <- newIORef []
  remainingFailures <- newIORef server.healthFailures
  settings <- newIORef server.storedSettings
  profile <- newIORef server.storedProfile
  let transport call = do
        modifyIORef' calls (<> [(call.method, call.path)])
        case (call.method, call.path) of
          (Get, "/health") -> do
            unhealthy <-
              atomicModifyIORef' remainingFailures \count -> (max 0 (count - 1), 0 < count)
            when unhealthy (throwM (UnexpectedStatus call.path 503))
            pure (Bool True)
          (Post, "/api/v1/auths/signin") -> pure server.signInResponse
          (Get, "/api/v1/users/user/settings") -> readIORef settings
          (Post, "/api/v1/users/user/settings/update") -> do
            for_ call.body (writeIORef settings)
            readIORef settings
          (Get, "/api/v1/auths/") -> toJSON <$> readIORef profile
          (Post, "/api/v1/auths/update/profile") -> do
            let posted = fields (fromMaybe Null call.body)
                keep column = foldMap (\value -> mempty & at column ?~ value) (posted ^? ix column)
                accepted = foldMap keep server.acceptedColumns
            modifyIORef' profile (accepted <>)
            toJSON <$> readIORef profile
          _ -> throwM (UnexpectedStatus call.path 404)
      environment =
        Environment
          { transport
          , -- 待たずに最大3回まで問い合わせ直す。
            healthRetry = limitRetries 3
          }
  result <- runSimpleNoLogEnv (tryAny (sync environment declaration))
  (result,,,) <$> readIORef calls <*> readIORef settings <*> readIORef profile

-- | 何も書き込まない時の呼び出し。
readOnly :: [(Method, Text)]
readOnly =
  [ (Get, "/health")
  , (Post, "/api/v1/auths/signin")
  , (Get, "/api/v1/users/user/settings")
  , (Get, "/api/v1/auths/")
  ]

-- | 失敗の型だけを取り出す。
failureOf :: (Exception e) => Either SomeException () -> Maybe e
failureOf = either fromException (const Nothing)

tests :: TopSpec
tests = describe "sync" do
  it "宣言と一致していれば、何も書き込まない" do
    (result, calls, _, _) <- synchronized synced
    isRight result `shouldBe` True
    calls `shouldBe` readOnly
  it "設定が宣言と違えば、宣言していない鍵を保ったまま書き込む" do
    (result, calls, settings, _) <-
      synchronized
        synced
          { storedSettings =
              [aesonQQ|{"ui": {"ctrlEnterToSend": false, "models": ["gpt-oss:120b"]}}|]
          }
    isRight result `shouldBe` True
    filter (== (Post, "/api/v1/users/user/settings/update")) calls
      `shouldBe` [(Post, "/api/v1/users/user/settings/update")]
    settings
      `shouldBe` [aesonQQ|{
        "ui": {"ctrlEnterToSend": true, "models": ["gpt-oss:120b"], "system": "こんにちは"}
      }|]
  it "設定を一度も書いたことが無い利用者にも書き込む" do
    (result, _, settings, _) <- synchronized synced{storedSettings = Null}
    isRight result `shouldBe` True
    settings `shouldBe` [aesonQQ|{"ui": {"ctrlEnterToSend": true, "system": "こんにちは"}}|]
  it "プロフィールが宣言と違えば書き込んで、収束したことを確かめる" do
    (result, calls, _, profile) <-
      synchronized
        synced{storedProfile = fields [aesonQQ|{"name": "User", "email": "admin@localhost"}|]}
    isRight result `shouldBe` True
    drop 3 calls
      `shouldBe` [ (Get, "/api/v1/auths/")
                 , (Post, "/api/v1/auths/update/profile")
                 , (Get, "/api/v1/auths/")
                 ]
    profile `shouldBe` synced.storedProfile
  it "上流が受け付けない列を宣言していたら、収束しないので失敗する" do
    (result, _, _, _) <-
      synchronized
        synced
          { storedProfile = fields [aesonQQ|{"name": "User"}|]
          , acceptedColumns = ["profile_image_url"]
          }
    failureOf result `shouldBe` Just ProfileNotConverged
  it "2回続けて同期したら、2回目は何も書き込まない" do
    (_, _, settings, profile) <-
      synchronized synced{storedSettings = Null, storedProfile = fields [aesonQQ|{"name": "User"}|]}
    (result, calls, _, _) <- synchronized synced{storedSettings = settings, storedProfile = profile}
    isRight result `shouldBe` True
    calls `shouldBe` readOnly
  it "Open WebUIが応答するまで待ってから進む" do
    (result, calls, _, _) <- synchronized synced{healthFailures = 2}
    isRight result `shouldBe` True
    take 4 calls
      `shouldBe` (replicate 3 (Get, "/health") <> [(Post, "/api/v1/auths/signin")])
  it "待ってもOpen WebUIが応答しなければ、サインインせずに失敗する" do
    (result, calls, _, _) <- synchronized synced{healthFailures = 10}
    failureOf result `shouldBe` Just (UnexpectedStatus "/health" 503)
    calls `shouldBe` replicate 4 (Get, "/health")
  for_
    [ ("トークンが無い", [aesonQQ|{"detail": "error"}|])
    , ("トークンがnullの", [aesonQQ|{"token": null}|])
    , ("トークンが空の", [aesonQQ|{"token": ""}|])
    ]
    \(name, response) ->
      it (name <> "サインインの応答なら、設定を取りに行かずに失敗する") do
        (result, calls, _, _) <- synchronized synced{signInResponse = response}
        failureOf result `shouldBe` Just MissingToken
        calls `shouldBe` take 2 readOnly
