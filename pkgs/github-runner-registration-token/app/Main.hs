module Main (main) where

import GithubRunnerRegistrationToken.Cli (run)
import Himari

main :: IO ()
main = runSimpleEnv (getArgs >>= run)
