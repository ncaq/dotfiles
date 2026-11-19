-- | 環境の種類ごとに、適用の間だけ最新のコミットの情報を注入するかのテスト。
module Spec.InstallSpec (tests) where

import DotfilesInstall.Architecture (Architecture (..))
import DotfilesInstall.Install (installWith)
import DotfilesInstall.LastCommit.Stage (lastCommitFile)
import DotfilesInstall.Platform (Platform (..))
import DotfilesInstall.SwitchCommand (SwitchCommand, switchCommand)
import Fixture
import Himari
import Test.Sandwich

-- | 適用のコマンドを走らせる代わりに、その時にstagingされているファイルと、渡されたコマンドを返す。
observe :: (MonadIO m) => FilePath -> Platform -> m (Text, SwitchCommand)
observe repository =
  quietly
    . installWith
      (\command -> (,command) <$> gitText repository ["diff", "--cached", "--name-only"])
      repository

tests :: TopSpec
tests = do
  describe "installWith" do
    it "NixOSでは適用の間だけ最新のコミットの情報を注入する" do
      withRepository \repository -> do
        let platform = NixOS "host"
        observe repository platform
          >>= (`shouldBe` (convert lastCommitFile, switchCommand platform))
        gitText repository ["status", "--porcelain"] >>= (`shouldBe` "")
        doesPathExist (repository </> lastCommitFile) >>= (`shouldBe` False)
    it "Nix-on-Droidでは注入しない" do
      withRepository \repository ->
        observe repository NixOnDroid >>= (`shouldBe` ("", switchCommand NixOnDroid))
    it "home-managerでは注入しない" do
      withRepository \repository -> do
        let platform = HomeManager X86_64
        observe repository platform >>= (`shouldBe` ("", switchCommand platform))
