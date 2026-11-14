-- | 設定を適用するコマンド。
module DotfilesInstall.SwitchCommand
  ( SwitchCommand (..)
  , switchCommand
  , commandLine
  ) where

import DotfilesInstall.Architecture (architectureSystem)
import DotfilesInstall.Platform (Platform (..))
import Himari

data SwitchCommand = SwitchCommand
  { program :: String
  , arguments :: [String]
  }
  deriving stock (Eq, Show)

-- | 環境の種類ごとの適用のコマンド。flakeは作業ディレクトリのものを指す。
switchCommand :: Platform -> SwitchCommand
switchCommand = \case
  NixOS hostName ->
    SwitchCommand "sudo" ["nixos-rebuild", "switch", "--flake", ".#" <> hostName]
  NixOnDroid ->
    SwitchCommand "nix-on-droid" ["switch", "--flake", "."]
  HomeManager architecture ->
    SwitchCommand
      "home-manager"
      ["--flake", ".#" <> architectureSystem architecture, "-b", "hm-bak", "switch"]

-- | ログに出すための1行の表記。
commandLine :: SwitchCommand -> Text
commandLine command = convert (unwords (command.program : command.arguments))
