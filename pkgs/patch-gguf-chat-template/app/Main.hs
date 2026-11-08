module Main (main) where

import Himari
import PatchGgufChatTemplate.Command (embed, extract)
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure)
import PatchGgufChatTemplate.Pad (PadFailure)

main :: IO ()
main = runSimpleEnv (handle (report @GgufFailure) (handle (report @PadFailure) run))
 where
  -- 扱えないファイルや長さの問題は想定している失敗なので、
  -- 例外の表示ではなく理由を1行で出して終わる。
  report :: forall e. (Exception e) => e -> Himari SimpleEnv ()
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)

run :: Himari SimpleEnv ()
run = do
  args <- getArgs
  case args of
    ["extract", ggufPath, templatePath] -> void (extract ggufPath templatePath)
    ["embed", ggufPath, templatePath] -> void (embed ggufPath templatePath)
    _ -> do
      logErrorN "使い方: patch-gguf-chat-template (extract|embed) <gguf> <template>"
      throwM (ExitFailure 1)
