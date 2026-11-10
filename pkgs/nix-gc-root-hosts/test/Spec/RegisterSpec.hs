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
  (\(outcome, warmed, entries, _) -> (outcome, warmed, entries))
    <$> registeredIn behavior \stateDirectory ->
      for_ existing \entry -> writeFile (stateDirectory </> entry) ""

-- | 状態ディレクトリを用意する操作を受け取って登録して、`registered`の結果に加えてログも返す。
registeredIn
  :: (MonadUnliftIO m)
  => Behavior
  -> (FilePath -> IO ())
  -> m (Either EvalFailed Outcome, [[Installable]], [FilePath], [Text])
registeredIn behavior prepare =
  withSystemTempDirectory "nix-gc-root-hosts-test" \stateDirectory -> do
    liftIO (prepare stateDirectory)
    logs <- newIORef []
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
      runSimpleEnvWith
        (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
        (try (register nix Config{stateDirectory, flake = "/etc/nixos-flake"}))
    (outcome,,,)
      <$> readIORef warmed
      <*> (sort <$> listDirectory stateDirectory)
      <*> readIORef logs

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
  it "まとめてのビルドが失敗したら、警告を出してから個別に続ける" do
    (outcome, _, entries, logs) <-
      registeredIn healthy{warmUpExit = ExitFailure 1} (const (pure ()))
    outcome `shouldBe` Right AllRegistered
    entries `shouldBe` allRoots
    logs `shouldBe` ["まとめてのビルドが終了コード1で失敗しました。個別に続けます"]
  it "全て成功したら何もログに出さない" do
    (_, _, _, logs) <- registeredIn healthy (const (pure ()))
    logs `shouldBe` []
  it "構成が1つも無ければ、まとめてのビルドを呼ばず、rootも作らない" do
    -- 引数の無い`nix build`はカレントディレクトリのflakeをビルドしようとする。
    -- 空の名前のrootを作ることも無い。
    registered healthy{hosts = Just [], systems = []} []
      >>= (`shouldBe` (Right AllRegistered, [], []))
  it "構成が1つも無くなったら、残っていたrootを全て消す" do
    registered healthy{hosts = Just [], systems = []} ["nixos-bullet"]
      >>= (`shouldBe` (Right AllRegistered, [], []))
  it "シンボリックリンクではない残骸も、種類を問わず消す" do
    -- `nix build`の中断などで、中身のあるディレクトリや切れたリンクが残ることがある。
    (outcome, _, entries, _) <-
      registeredIn healthy \stateDirectory -> do
        createDirectory (stateDirectory </> "nixos-debris")
        writeFile (stateDirectory </> "nixos-debris" </> "partial") "partial"
        createFileLink "/nonexistent/store/path" (stateDirectory </> "nixos-dangling")
    outcome `shouldBe` Right AllRegistered
    entries `shouldBe` allRoots
