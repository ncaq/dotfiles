-- | リモートのURLの検証のテスト。
module Spec.RemoteUrlSpec (tests) where

import GitRepoSubscribe.Failure (RemoteUrlError (..))
import GitRepoSubscribe.RemoteUrl
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parseRemoteUrl" do
  -- Gitが保存しているURLと文字列として比べるので、受け付けた綴りは一字も変えない。
  for_
    [ "https://github.com/NixOS/nixpkgs.git"
    , "https://example.com:8443/path/to/repo.git"
    , "https://example.com/a%20b.git"
    , "ssh://git@github.com/NixOS/nixpkgs.git"
    , "ssh://git@github.com:22/NixOS/nixpkgs.git"
    , "file:///tmp/repository.git"
    , "file://localhost/tmp/repository.git"
    ]
    \url ->
      it (convert url <> "を綴りを変えずに受け付ける") do
        (remoteUrlText <$> parseRemoteUrl url) `shouldBe` Right url
  it "scp形式はURLとして読めない" do
    parseRemoteUrl "git@github.com:NixOS/nixpkgs.git" `shouldBe` Left InvalidUrlSyntax
  it "対応していないスキームはそのスキームを報告する" do
    parseRemoteUrl "git://github.com/NixOS/nixpkgs.git" `shouldBe` Left (UnsupportedScheme "git")
  -- Gitは大文字のスキームを扱えず、Nix側の型検査も小文字しか通さない。
  it "大文字のスキームは対応していないスキームとして拒否する" do
    parseRemoteUrl "HTTPS://github.com/NixOS/nixpkgs.git"
      `shouldBe` Left (UnsupportedScheme "HTTPS")
  for_
    [ "https:example.com/repo.git"
    , "file:relative/repo.git"
    , "https:///repo.git"
    , "ssh:///repo.git"
    ]
    \url ->
      it (convert url <> "はホストが無いので拒否する") do
        parseRemoteUrl url `shouldBe` Left UrlMissingHost
  it "パスワードを含むURLを拒否する" do
    parseRemoteUrl "https://user:password@example.com/repo.git" `shouldBe` Left UrlPassword
  it "SSHでもパスワードを含むURLを拒否する" do
    parseRemoteUrl "ssh://git:password@example.com/repo.git" `shouldBe` Left UrlPassword
  it "HTTPSのユーザ名を拒否する" do
    parseRemoteUrl "https://token@example.com/repo.git" `shouldBe` Left UrlUsername
  it "fileのユーザ名を拒否する" do
    parseRemoteUrl "file://user@host/tmp/repository.git" `shouldBe` Left UrlUsername
  it "改行を拒否する" do
    parseRemoteUrl "https://example.com/repo.git\n" `shouldBe` Left UrlUnsafeCharacter
  it "制御文字を拒否する" do
    parseRemoteUrl "https://example.com/repo.git\ESC" `shouldBe` Left UrlUnsafeCharacter
  it "バックスラッシュを拒否する" do
    parseRemoteUrl "https://user\\@example.com/repo.git" `shouldBe` Left UrlBackslash
