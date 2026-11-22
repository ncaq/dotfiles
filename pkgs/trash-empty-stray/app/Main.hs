module Main (main) where

import Himari
import TrashEmptyStray.Cli (run)

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
