module Main (main) where

import Himari
import RemovableCrypt.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
