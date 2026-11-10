module Main (main) where

import Himari
import UserSettingsSync.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
