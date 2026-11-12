-- | アクセストークンの読み方のテスト。
module Spec.AccessTokenSpec (tests) where

import GithubRunnerRegistrationToken.AccessToken (AccessToken, readAccessToken)
import GithubRunnerRegistrationToken.Failure (ConfigFailure (..))
import Himari
import Test.Sandwich

-- | 一時ディレクトリに中身を書いたファイルを置いて、そのパスを渡す。
withTokenFile :: (MonadUnliftIO m) => String -> (FilePath -> m a) -> m a
withTokenFile content action =
  withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
    let path = directory </> "pat"
    liftIO (writeFile path content)
    action path

tests :: TopSpec
tests = describe "AccessToken" do
  it "ファイルの末尾の改行を落として読む" do
    withTokenFile "github_pat_example\n" (readAccessToken >=> (`shouldBe` "github_pat_example"))
  it "CRLFの改行も落とす" do
    withTokenFile
      "github_pat_example\r\n"
      (readAccessToken >=> (`shouldBe` "github_pat_example"))
  it "前後の空白も落とす" do
    withTokenFile
      "  github_pat_example \n"
      (readAccessToken >=> (`shouldBe` "github_pat_example"))
  it "空のファイルは失敗にする" do
    withTokenFile "" \path ->
      readAccessToken path `shouldThrow` (== EmptyAccessToken path)
  it "空白と改行だけのファイルも失敗にする" do
    withTokenFile " \r\n" \path ->
      readAccessToken path `shouldThrow` (== EmptyAccessToken path)
  it "表示しても中身を出さない" do
    show ("github_pat_example" :: AccessToken) `shouldBe` "AccessToken <redacted>"
