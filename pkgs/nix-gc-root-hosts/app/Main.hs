module Main (main) where

import Himari
import NixGcRootHosts.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
