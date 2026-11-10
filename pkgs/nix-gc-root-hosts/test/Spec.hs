{-# OPTIONS_GHC -F -pgmF sandwich-discover #-}
{-# OPTIONS_GHC -Wno-type-defaults #-}

module Spec (tests) where

import Test.Sandwich

#insert_test_imports

tests :: TopSpec
tests = $(getSpecFromFolder defaultGetSpecFromFolderOptions)
