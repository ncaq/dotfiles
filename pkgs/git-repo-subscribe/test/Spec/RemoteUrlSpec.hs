-- | リモートのURLの検証のテスト。
module Spec.RemoteUrlSpec (tests) where

import GitRepoSubscribe.Failure (RemoteUrlError (..))
import GitRepoSubscribe.RemoteUrl
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parseRemoteUrl" do
  for_
    [ "https://github.com/NixOS/nixpkgs.git"
    , "ssh://git@github.com/NixOS/nixpkgs.git"
    , "file:///tmp/repository.git"
    ]
    \url ->
      it (convert url <> "を綴りを変えずに受け付ける") do
        (remoteUrlText <$> parseRemoteUrl url) `shouldBe` Right url
  it "scp形式はURLとして読めない" do
    parseRemoteUrl "git@github.com:NixOS/nixpkgs.git" `shouldBe` Left InvalidUrlSyntax
  it "対応していないスキームはそのスキームを報告する" do
    parseRemoteUrl "git://github.com/NixOS/nixpkgs.git" `shouldBe` Left (UnsupportedScheme "git")
  it "パスワードを含むURLを拒否する" do
    parseRemoteUrl "https://user:password@example.com/repo.git" `shouldBe` Left UrlPassword
  it "HTTPSのユーザ名を拒否する" do
    parseRemoteUrl "https://token@example.com/repo.git" `shouldBe` Left UrlUsername
  it "改行を拒否する" do
    parseRemoteUrl "https://example.com/repo.git\n" `shouldBe` Left UrlUnsafeCharacter
  it "制御文字を拒否する" do
    parseRemoteUrl "https://example.com/repo.git\ESC" `shouldBe` Left UrlUnsafeCharacter
  it "バックスラッシュを拒否する" do
    parseRemoteUrl "https://user\\@example.com/repo.git" `shouldBe` Left UrlBackslash
