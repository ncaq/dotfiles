module Main (main) where

import Himari
import IdleFreeMemory.Run (Config (..), run)

main :: IO ()
main = runSimpleEnv do
  -- 受け取るのはホストとポートだけで、スキームはこちらが決める。
  authority <- convert <$> getEnv "COMFYUI_AUTHORITY"
  pollIntervalSeconds <- secondsFrom "POLL_INTERVAL_SECONDS"
  idleSeconds :: Int <- secondsFrom "IDLE_SECONDS"
  run Config{authority, pollIntervalSeconds, idleThreshold = fromIntegral idleSeconds}
 where
  -- 秒数は正の整数で受け取る。
  -- 読めない値で動き出すと、待たずに回り続けるか永久に解放しないかのどちらかになるので、
  -- 起動の時点で落とす。
  secondsFrom name = do
    raw <- getEnv name
    case readMay raw of
      Just seconds | 0 < seconds -> pure seconds
      _ -> do
        logErrorN (convert name <> "は正の整数の秒数で指定してください: " <> convert raw)
        throwM (ExitFailure 1)
