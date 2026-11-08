module Main (main) where

import Himari
import PatchGgufChatTemplate.Cli (run)

main :: IO ()
main = runSimpleEnv (void (getArgs >>= run))
