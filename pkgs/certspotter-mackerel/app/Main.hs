module Main (main) where

import CertspotterMackerel.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
