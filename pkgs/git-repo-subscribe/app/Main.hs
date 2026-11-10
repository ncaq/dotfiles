module Main (main) where

import GitRepoSubscribe.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
