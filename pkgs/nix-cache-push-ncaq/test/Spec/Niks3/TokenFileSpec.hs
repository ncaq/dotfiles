-- | 認証トークンの一時ファイルのテスト。
module Spec.Niks3.TokenFileSpec (tests) where

import Data.Text.IO.Utf8 (readFile)
import Himari hiding (readFile)
import NixCachePushNcaq.Failure (ConfigFailure (..))
import NixCachePushNcaq.MountInfo (Mount (..), fileSystemOf, parseMountInfo)
import NixCachePushNcaq.Niks3.TokenFile (systemTokenDirectory, tokenDirectoryFrom, withTokenFile)
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Sandwich

-- | 一時ファイルを置くディレクトリを作って渡す。
withDirectory :: (MonadUnliftIO m) => (FilePath -> m a) -> m a
withDirectory = withSystemTempDirectory "nix-cache-push-ncaq-test"

-- | 候補にする2つのディレクトリを作って、シンボリックリンクを辿った後のパスで渡す。
--
-- マウントの一覧はテストが手書きで渡すので、
-- 実際にどのファイルシステムの上にあるかには左右されない。
withCandidates :: (MonadUnliftIO m) => (FilePath -> FilePath -> m a) -> m a
withCandidates action =
  withDirectory \directory -> do
    root <- canonicalizePath directory
    let first = root </> "first"
        second = root </> "second"
    traverse_ createDirectory [first, second]
    action first second

-- | 全体をディスクの上に置いた上で、指定のディレクトリだけをtmpfsにしたマウントの一覧。
tmpfsAt :: [FilePath] -> [Mount]
tmpfsAt directories =
  Mount{mountPoint = "/", fileSystem = "btrfs"}
    : fmap (\directory -> Mount{mountPoint = directory, fileSystem = "tmpfs"}) directories

-- | 処理の途中で投げる例外。
data Interrupted = Interrupted
  deriving stock (Eq, Show)

instance Exception Interrupted

tests :: TopSpec
tests = describe "TokenFile" do
  describe "withTokenFile" do
    it "指定のディレクトリに、トークンだけを書いたファイルを作る" do
      withDirectory \directory ->
        withTokenFile directory "token-example" \path -> do
          takeDirectory path `shouldBe` directory
          liftIO (readFile path) >>= (`shouldBe` "token-example")
    it "所有者だけが読み書きできる" do
      withDirectory \directory ->
        withTokenFile directory "token-example" \path -> do
          status <- liftIO (getFileStatus path)
          intersectFileModes (fileMode status) 0o777 `shouldBe` 0o600
    it "処理が終わったら消す" do
      withDirectory \directory -> do
        path <- withTokenFile directory "token-example" pure
        doesFileExist path >>= (`shouldBe` False)
        listDirectory directory >>= (`shouldBe` [])
    it "処理が例外で終わっても消す" do
      withDirectory \directory -> do
        withTokenFile directory "token-example" (const (throwM Interrupted))
          `shouldThrow` (== Interrupted)
        listDirectory directory >>= (`shouldBe` [])
  describe "tokenDirectoryFrom" do
    it "tmpfsの候補が複数あれば最初のものを選ぶ" do
      withCandidates \first second ->
        tokenDirectoryFrom (tmpfsAt [first, second]) [first, second] >>= (`shouldBe` first)
    it "tmpfsでない候補は飛ばす" do
      withCandidates \first second ->
        tokenDirectoryFrom (tmpfsAt [second]) [first, second] >>= (`shouldBe` second)
    it "存在しない候補は、マウントの一覧でtmpfsの下にあっても飛ばす" do
      withCandidates \first second -> do
        let missing = takeDirectory first </> "missing"
        tokenDirectoryFrom (tmpfsAt [takeDirectory first]) [missing, second]
          >>= (`shouldBe` second)
    it "tmpfsの候補が無ければ失敗にする" do
      withCandidates \first second ->
        tokenDirectoryFrom (tmpfsAt []) [first, second] `shouldThrow` (== NoTmpfsDirectory)
    it "候補が無ければ失敗にする" do
      tokenDirectoryFrom (tmpfsAt []) [] `shouldThrow` (== NoTmpfsDirectory)
  describe "systemTokenDirectory" do
    -- どこを選ぶかは環境によるので固定しない。選んだ場所がtmpfsであることだけを確かめる。
    it "このマシンのマウントの一覧でtmpfsである場所を選ぶ" do
      directory <- systemTokenDirectory Nothing >>= canonicalizePath
      mounts <- liftIO (readFile "/proc/self/mountinfo") >>= parseMountInfo
      fileSystemOf mounts directory `shouldBe` Just "tmpfs"
    it "tmpfsでないXDG_RUNTIME_DIRは使わない" do
      withDirectory \directory -> do
        mounts <- liftIO (readFile "/proc/self/mountinfo") >>= parseMountInfo
        notOnTmpfs <- (/= Just "tmpfs") . fileSystemOf mounts <$> canonicalizePath directory
        -- 作業ディレクトリがtmpfsの環境では、このテストは確かめるものが無い。
        when notOnTmpfs do
          systemTokenDirectory (Just directory) >>= (`shouldNotBe` directory)
