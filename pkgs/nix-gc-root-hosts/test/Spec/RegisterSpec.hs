-- | 登録と掃除を通しで行うテスト。
--
-- `nix`は記録するだけの偽物に差し替えて、状態ディレクトリは一時ディレクトリにする。
module Spec.RegisterSpec (tests) where

import Data.List (sort)
import Himari
import NixGcRootHosts.Config (Config (..))
import NixGcRootHosts.Installable (Installable)
import NixGcRootHosts.Nix (Nix (..))
import NixGcRootHosts.Register (Outcome (..), register)
import Test.Sandwich

-- | 構成の列挙に失敗したことを表す、偽の`nix`の例外。
data EvalFailed = EvalFailed
  deriving stock (Eq, Show)

instance Exception EvalFailed

-- | 偽の`nix`の振る舞い。
data Behavior = Behavior
  { hosts :: Maybe [Text]
  -- ^ `nixosConfigurations`の名前。`Nothing`なら列挙に失敗する。
  , systems :: [Text]
  -- ^ `homeConfigurations`の名前。
  , warmUpExit :: ExitCode
  , failing :: [Installable]
  -- ^ out-linkを張る時に失敗するinstallable。
  }

-- | 2つのホストと1つのシステムがあり、全て成功する。
healthy :: Behavior
healthy =
  Behavior
    { hosts = Just ["bullet", "seminar"]
    , systems = ["x86_64-linux"]
    , warmUpExit = ExitSuccess
    , failing = []
    }

-- | 登録して、結果と、まとめてのビルドへ渡されたinstallableと、状態ディレクトリの中身を返す。
--
-- 先に状態ディレクトリへ置いておく名前を受け取る。
registered
  :: (MonadUnliftIO m)
  => Behavior
  -> [FilePath]
  -> m (Either EvalFailed Outcome, [[Installable]], [FilePath])
registered behavior existing =
  withSystemTempDirectory "nix-gc-root-hosts-test" \stateDirectory -> do
    for_ existing \entry -> liftIO (writeFile (stateDirectory </> entry) "")
    warmed <- newIORef []
    let nix =
          Nix
            { attrNames = \_ -> \case
                "nixosConfigurations" -> maybe (throwM EvalFailed) pure behavior.hosts
                _ -> pure behavior.systems
            , warmUp = \installables ->
                behavior.warmUpExit <$ modifyIORef' warmed (<> [installables])
            , link = \installable path ->
                if installable `elem` behavior.failing
                  then pure (ExitFailure 1)
                  else ExitSuccess <$ liftIO (writeFile path "linked")
            }
    outcome <-
      runSimpleNoLogEnv
        (try (register nix Config{stateDirectory, flake = "/etc/nixos-flake"}))
    (outcome,,) <$> readIORef warmed <*> (sort <$> listDirectory stateDirectory)

bullet :: Installable
bullet = "/etc/nixos-flake#nixosConfigurations.bullet.config.system.build.toplevel"

seminar :: Installable
seminar = "/etc/nixos-flake#nixosConfigurations.seminar.config.system.build.toplevel"

home :: Installable
home = "/etc/nixos-flake#homeConfigurations.x86_64-linux.activationPackage"

allRoots :: [FilePath]
allRoots = ["home-manager-x86_64-linux", "nixos-bullet", "nixos-seminar"]

tests :: TopSpec
tests = describe "register" do
  it "全ての構成をまとめてビルドしてから、それぞれのrootを張る" do
    registered healthy []
      >>= (`shouldBe` (Right AllRegistered, [[bullet, seminar, home]], allRoots))
  it "今の構成に無いrootを消して、ある分は残す" do
    registered healthy ["nixos-bullet", "nixos-removed", "home-manager-aarch64-linux"]
      >>= (`shouldBe` (Right AllRegistered, [[bullet, seminar, home]], allRoots))
  it "まとめてのビルドが失敗しても、個別に続けて成功すれば成功にする" do
    registered healthy{warmUpExit = ExitFailure 1} []
      >>= (`shouldBe` (Right AllRegistered, [[bullet, seminar, home]], allRoots))
  it "張れなかったrootがあれば名前を返して、残りは張る" do
    registered healthy{failing = [seminar]} []
      >>= ( `shouldBe`
              ( Right (SomeFailed ["nixos-seminar"])
              , [[bullet, seminar, home]]
              , ["home-manager-x86_64-linux", "nixos-bullet"]
              )
          )
  it "張れなかったrootの前回のリンクは消さない" do
    -- 今回ビルドできなくても、前回の閉包を守り続ける方が良い。
    registered healthy{failing = [seminar]} ["nixos-seminar", "nixos-removed"]
      >>= ( `shouldBe`
              ( Right (SomeFailed ["nixos-seminar"])
              , [[bullet, seminar, home]]
              , allRoots
              )
          )
  it "構成の列挙に失敗したら、何も消さずに中断する" do
    -- 空の一覧のまま掃除へ進むと、既存のrootを全て消してしまう。
    registered healthy{hosts = Nothing} ["nixos-bullet", "nixos-seminar"]
      >>= (`shouldBe` (Left EvalFailed, [], ["nixos-bullet", "nixos-seminar"]))
