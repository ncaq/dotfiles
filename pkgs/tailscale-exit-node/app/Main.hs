module Main (main) where

import Himari
import TailscaleExitNode.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
