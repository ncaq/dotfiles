-- | コマンドラインの引数の解釈と、失敗の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意して引数をここへ渡すだけにして、
-- `lib/patch-gguf-chat-template.nix`が実際に呼ぶ形での振る舞いをsandwichで検査できるようにする。
-- `embed`が失敗しても0で終わるように変わると、
-- fixed-output derivationのhashの不一致としてしか現れず原因を突き止めにくい。
module PatchGgufChatTemplate.Cli
  ( Command (..)
  , parseArgs
  , run
  ) where

import Himari
import PatchGgufChatTemplate.Command (embed, extract)
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure)
import PatchGgufChatTemplate.Gguf.Locate (Span)
import PatchGgufChatTemplate.Pad (PadFailure)

-- | 引数から解釈したコマンド。どちらもGGUFのパスとテンプレートのパスを取る。
data Command
  = Extract FilePath FilePath
  | Embed FilePath FilePath
  deriving stock (Eq, Show)

-- | 引数を解釈する。形が違えば`Nothing`。
parseArgs :: [String] -> Maybe Command
parseArgs = \case
  ["extract", ggufPath, templatePath] -> Just (Extract ggufPath templatePath)
  ["embed", ggufPath, templatePath] -> Just (Embed ggufPath templatePath)
  _ -> Nothing

-- | 引数を解釈してコマンドを実行し、触ったテンプレートの位置を返す。
--
-- 引数の形が違う場合と、扱えないファイルや長さの問題は想定している失敗なので、
-- 例外の表示ではなく理由を1行でログに出して`ExitFailure 1`にする。
-- それ以外の例外はこちらの不具合なので変換せずに通す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m Span
run args = case parseArgs args of
  Nothing -> do
    logErrorN "使い方: patch-gguf-chat-template (extract|embed) <gguf> <template>"
    throwM (ExitFailure 1)
  Just command ->
    handle (report @GgufFailure) $ handle (report @PadFailure) case command of
      Extract ggufPath templatePath -> extract ggufPath templatePath
      Embed ggufPath templatePath -> embed ggufPath templatePath
 where
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
