-- | 全ホストの閉包をGC rootとして登録する。
--
-- セルフホストランナーはこのホストのnix storeを共有しているが、
-- `nix build`のresultリンクはephemeralなランナーコンテナ内にあるため、
-- ジョブ終了後は他ホスト向けの閉包を守るrootが残らない。
-- そのままGCに回収されると、次のCIで巨大なパスを取得し直すことになる。
-- <https://github.com/ncaq/dotfiles/issues/1535>
--
-- flakeの`nixosConfigurations`と`homeConfigurations`を動的に列挙するので、
-- flakeへ構成を追加すると自動で追従する。
-- `nixOnDroidConfigurations`は列挙の対象に含めない。
-- QEMUエミュレーション経由のビルドが遅く、
-- モデルファイルのような巨大なパスも含まれないためである。
module NixGcRootHosts.Register
  ( Outcome (..)
  , register
  ) where

import Himari
import NixGcRootHosts.Config (Config (..))
import NixGcRootHosts.Installable (Installable (..))
import NixGcRootHosts.Nix (Nix (..))
import NixGcRootHosts.Root (Root (..), homeRoot, nixosRoot)
import NixGcRootHosts.RootName (RootName (..))
import NixGcRootHosts.Stale (staleEntries)

-- | 登録の結果。
data Outcome
  = AllRegistered
  | -- | 登録できなかったrootがある。その名前。
    SomeFailed [RootName]
  deriving stock (Eq, Show)

-- | 全ての構成のrootを登録して、今の構成に対応しないrootを消す。
--
-- 構成の列挙に失敗した時は例外で中断する。
-- 空の一覧のまま進むと、後段の掃除で既存のrootを全て消してしまう。
register :: (MonadLogger m, MonadUnliftIO m) => Nix m -> Config -> m Outcome
register nix config = do
  roots <-
    liftA2
      (<>)
      (fmap (nixosRoot config.flake) <$> nix.attrNames config.flake "nixosConfigurations")
      (fmap (homeRoot config.flake) <$> nix.attrNames config.flake "homeConfigurations")
  -- 先に全てを1回の`nix build`へまとめて渡す。
  -- 1つずつビルドすると評価プロセスがその都度立ち上がる上に、
  -- ダウンロードとビルドが構成間で全く重ならない。
  -- まとめて渡せばNixのスケジューラが構成を横断して並列に処理する。
  -- 失敗は後段のout-linkで個別に検知するので、ここでは記録だけ残して進む。
  --
  -- 構成が1つも無い時は呼ばない。
  -- installableの無い`nix build`は、カレントディレクトリのflakeをビルドしようとする。
  unless (null roots) do
    nix.warmUp (fmap (.installable) roots) >>= \case
      ExitSuccess -> pure ()
      ExitFailure code ->
        logWarnN ("まとめてのビルドが終了コード" <> convert (show code) <> "で失敗しました。個別に続けます")
  -- まとめてのビルドで成果物が揃っているので、
  -- ここの個別のビルドはout-linkを張るだけでほぼ即座に終わる。
  failed <- catMaybes <$> traverse linkRoot roots
  removeStale (fmap (.name) roots)
  pure (if null failed then AllRegistered else SomeFailed failed)
 where
  linkRoot root = do
    let RootName name = root.name
        Installable installable = root.installable
    nix.link root.installable (config.stateDirectory </> convert name) >>= \case
      ExitSuccess -> pure Nothing
      ExitFailure code -> do
        logErrorN (installable <> "のビルドが終了コード" <> convert (show code) <> "で失敗しました")
        pure (Just root.name)
  removeStale names = do
    entries <- listDirectory config.stateDirectory
    -- `nix build`の中断などでシンボリックリンク以外の残骸が紛れ込んでいても、
    -- 消せずに途中で終わらないように、種類を問わず消す。
    for_ (staleEntries names entries) \entry -> do
      logInfoN ("今の構成に無いrootを消します: " <> convert entry)
      removePathForcibly (config.stateDirectory </> entry)
