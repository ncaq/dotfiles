module Main (main) where

import DotfilesInstall.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
