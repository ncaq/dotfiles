module Main (main) where

import Himari
import NixCachePushNcaq.Cachix.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
