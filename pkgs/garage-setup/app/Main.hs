module Main (main) where

import GarageSetup.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
