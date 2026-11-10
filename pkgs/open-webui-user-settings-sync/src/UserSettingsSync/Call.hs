-- | Open WebUIのAPIの1回の呼び出し。
--
-- 何を送るかを値として組み立ててから送るので、送る内容をHTTPに触れずに検査できる。
module UserSettingsSync.Call
  ( Call (..)
  , Method (..)
  , health
  , signIn
  , getSettings
  , updateSettings
  , getProfile
  , updateProfile
  ) where

import Himari
import UserSettingsSync.Token (Token)

data Method
  = Get
  | Post
  deriving stock (Eq, Show)

data Call = Call
  { method :: Method
  , path :: Text
  , authorization :: Maybe Token
  , body :: Maybe Value
  }
  deriving stock (Eq, Show)

-- | 起動しているかを確かめる。
health :: Call
health = Call{method = Get, path = "/health", authorization = Nothing, body = Nothing}

-- | `WEBUI_AUTH`を無効にしたインスタンスのadminとしてサインインする。
--
-- この組は`routers/auths.py`のsigninが無効時に使う定数そのもので、
-- 秘密ではなく、認証が無効である以上これ以外の資格情報は存在しない。
signIn :: Call
signIn =
  Call
    { method = Post
    , path = "/api/v1/auths/signin"
    , authorization = Nothing
    , body = Just [aesonQQ|{"email": "admin@localhost", "password": "admin"}|]
    }

-- | 利用者の設定を取る。一度も書かれていなければ応答は`null`になる。
--
-- Modelの登録と違い、この経路はトークンを要求する。
getSettings :: Token -> Call
getSettings token =
  Call
    { method = Get
    , path = "/api/v1/users/user/settings"
    , authorization = Just token
    , body = Nothing
    }

newtype SettingsUpdate = SettingsUpdate
  { ui :: Map Text Value
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] SettingsUpdate

-- | 利用者の設定の`ui`を置き換える。
updateSettings :: Token -> Map Text Value -> Call
updateSettings token ui =
  Call
    { method = Post
    , path = "/api/v1/users/user/settings/update"
    , authorization = Just token
    , body = Just (toJSON SettingsUpdate{ui})
    }

-- | サインインしている利用者のプロフィールを取る。
getProfile :: Token -> Call
getProfile token =
  Call{method = Get, path = "/api/v1/auths/", authorization = Just token, body = Nothing}

-- | プロフィールの列を書き換える。
updateProfile :: Token -> Map Text Value -> Call
updateProfile token profile =
  Call
    { method = Post
    , path = "/api/v1/auths/update/profile"
    , authorization = Just token
    , body = Just (toJSON profile)
    }
