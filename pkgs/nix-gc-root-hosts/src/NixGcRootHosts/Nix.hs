-- | `nix`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際の評価やビルドをせずに済ませるためである。
module NixGcRootHosts.Nix
  ( Nix (..)
  , systemNix
  ) where

import Himari
import NixGcRootHosts.Failure (NixFailure (..))
import NixGcRootHosts.Flake (Flake (..))
import NixGcRootHosts.Installable (Installable (..))

data Nix m = Nix
  { attrNames :: Flake -> Text -> m [Text]
  -- ^ flakeの出力の属性集合が持つ名前を列挙する。失敗したら例外を投げる。
  , warmUp :: [Installable] -> m ExitCode
  -- ^ 全てをまとめてビルドする。リンクは張らない。
  , link :: Installable -> FilePath -> m ExitCode
  -- ^ ビルドして、指定のパスへout-linkを張る。
  }

-- | PATHにある`nix`を呼ぶ。
systemNix :: (MonadIO m, MonadThrow m) => Nix m
systemNix =
  Nix
    { attrNames = \(Flake flake) attribute -> do
        output <-
          readProcessStdout_
            (nix ["eval", "--json", convert (flake <> "#" <> attribute), "--apply", names])
        either (throwM . UndecodableAttrNames attribute . convert) pure (eitherDecode output)
    , warmUp = \installables ->
        runProcess (nix (["build", "--keep-going", "--no-link"] <> fmap word installables))
    , link = \installable path ->
        runProcess (nix ["build", word installable, "--out-link", path])
    }
 where
  nix = proc "nix"
  names = "builtins.attrNames"
  word (Installable installable) = convert installable
