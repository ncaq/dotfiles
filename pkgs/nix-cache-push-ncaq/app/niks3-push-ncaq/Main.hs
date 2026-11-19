module Main (main) where

import Himari
import NixCachePushNcaq.Niks3.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
