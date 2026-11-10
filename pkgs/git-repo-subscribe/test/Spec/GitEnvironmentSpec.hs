-- | Gitへ渡す環境変数のテスト。
module Spec.GitEnvironmentSpec (tests) where

import GitRepoSubscribe.Git.Environment
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "gitEnvironment" do
  for_
    [ ("GIT_TERMINAL_PROMPT", "0")
    , ("GIT_CONFIG_GLOBAL", "/dev/null")
    , ("GIT_CONFIG_NOSYSTEM", "1")
    , ("GIT_CONFIG_SYSTEM", "/dev/null")
    , ("GIT_ASKPASS", "false")
    , ("SSH_ASKPASS", "false")
    , ("GIT_HTTP_LOW_SPEED_LIMIT", "1")
    , ("GIT_HTTP_LOW_SPEED_TIME", "60")
    ]
    \(name, value) ->
      it (name <> "を" <> value <> "に固定する") do
        -- 継いだ値があっても、固定の値だけが残る。
        filter ((== name) . fst) (gitEnvironment [(name, "inherited")]) `shouldBe` [(name, value)]
  it "SSHを対話させず、接続を60秒で打ち切らせる" do
    lookup "GIT_SSH_COMMAND" (gitEnvironment [])
      `shouldBe` Just
        "ssh -oBatchMode=yes -oConnectTimeout=60 -oServerAliveInterval=15 -oServerAliveCountMax=4"
  for_
    [ "GIT_ALTERNATE_OBJECT_DIRECTORIES"
    , "GIT_CEILING_DIRECTORIES"
    , "GIT_COMMON_DIR"
    , "GIT_CONFIG"
    , "GIT_CONFIG_COUNT"
    , "GIT_CONFIG_PARAMETERS"
    , "GIT_DIR"
    , "GIT_DISCOVERY_ACROSS_FILESYSTEM"
    , "GIT_EXEC_PATH"
    , "GIT_GRAFT_FILE"
    , "GIT_INDEX_FILE"
    , "GIT_NAMESPACE"
    , "GIT_OBJECT_DIRECTORY"
    , "GIT_PROXY_COMMAND"
    , "GIT_SHALLOW_FILE"
    , "GIT_SSH_VARIANT"
    , "GIT_TEMPLATE_DIR"
    , "GIT_WORK_TREE"
    ]
    \name ->
      it (name <> "を取り除く") do
        lookup name (gitEnvironment [(name, "inherited")]) `shouldBe` Nothing
  it "関係のない変数はそのまま継ぐ" do
    lookup "PATH" (gitEnvironment [("PATH", "/bin")]) `shouldBe` Just "/bin"
