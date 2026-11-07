module Main (main) where

import Himari
import IdleFreeMemory.Config (Config (..), parseSeconds)
import IdleFreeMemory.Run (run)

main :: IO ()
main = runSimpleEnv do
  -- 受け取るのはホストとポートだけで、スキームはこちらが決める。
  authority <- convert <$> getEnv "COMFYUI_AUTHORITY"
  pollIntervalSeconds <- secondsFrom "POLL_INTERVAL_SECONDS"
  idleSeconds <- secondsFrom "IDLE_SECONDS"
  run Config{authority, pollIntervalSeconds, idleThreshold = fromIntegral idleSeconds}
 where
  secondsFrom name = do
    raw <- getEnv name
    case parseSeconds raw of
      Just seconds -> pure seconds
      Nothing -> do
        logErrorN (convert name <> "は正の整数の秒数で指定してください: " <> convert raw)
        throwM (ExitFailure 1)
