module Main (main) where

import Himari
import WifiWiredExclusive.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
