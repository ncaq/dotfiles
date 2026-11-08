module Main (main) where

import Himari
import NvdPrDiff.Cli (run)

main :: IO ()
main = runSimpleEnv (void run)
