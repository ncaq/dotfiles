-- | 時間の長さの、マイクロ秒の整数への変換。
module GithubRunnerRegistrationToken.Microseconds
  ( microseconds
  ) where

import Himari

-- | 時間の長さをマイクロ秒の整数にする。マイクロ秒より細かい端数は切り捨てる。
--
-- 試し直しの間隔はマイクロ秒の`Int`で受け渡される。
-- 桁の多い数値をそのまま書かずに、秒で書いた長さから求めるために使う。
microseconds :: NominalDiffTime -> Int
microseconds duration = fromInteger count
 where
  MkFixed count = realToFrac duration :: Micro
