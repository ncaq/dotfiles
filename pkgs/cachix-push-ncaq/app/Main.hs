module Main (main) where

import CachixPushNcaq.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
