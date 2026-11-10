-- | Gitの子プロセスへ渡す環境変数。
module GitRepoSubscribe.Git.Environment
  ( gitEnvironment
  ) where

import Himari

-- | 継いだ環境変数から、Gitへ渡す環境変数を作る。
--
-- 操作の対象や設定の探し方を差し替えられる変数は取り除き、
-- グローバルとシステムの設定を読ませず、認証の入力を求めさせない値を足す。
-- 通信が止まった時は60秒で打ち切らせる。
gitEnvironment :: [(String, String)] -> [(String, String)]
gitEnvironment inherited =
  fixed <> filter (\(name, _) -> name `notElem` (removed <> (fst <$> fixed))) inherited
 where
  fixed =
    [ ("GIT_CONFIG_GLOBAL", "/dev/null")
    , ("GIT_CONFIG_NOSYSTEM", "1")
    , ("GIT_CONFIG_SYSTEM", "/dev/null")
    , ("GIT_TERMINAL_PROMPT", "0")
    , ("GIT_ASKPASS", "false")
    , ("SSH_ASKPASS", "false")
    ,
      ( "GIT_SSH_COMMAND"
      , "ssh -oBatchMode=yes -oConnectTimeout=60 -oServerAliveInterval=15 -oServerAliveCountMax=4"
      )
    , ("GIT_HTTP_LOW_SPEED_LIMIT", "1")
    , ("GIT_HTTP_LOW_SPEED_TIME", "60")
    ]
  removed =
    [ "GIT_ALTERNATE_OBJECT_DIRECTORIES"
    , "GIT_COMMON_DIR"
    , "GIT_CEILING_DIRECTORIES"
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
