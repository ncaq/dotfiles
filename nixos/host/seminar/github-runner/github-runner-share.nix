{ config, pkgs, ... }:
let
  # GitHubの標準ランナーにはないけれど個人的に含まれていて欲しいパッケージリスト。
  selfHostRunnerPackages = with pkgs; [
    attic-client
    cachix
  ];
  # GitHub Actionsのホステッドランナーをある程度互換しているパッケージリスト。
  githubActionsRunnerPackages = import ../../../../lib/github-actions-runner-packages.nix {
    inherit pkgs;
  };
  # GitHub Actionsのランナー向けの全部盛りパッケージリスト。
  githubRunnerPackagesAll = githubActionsRunnerPackages.all ++ selfHostRunnerPackages;
  # GitHub Actionsのランナー向けの最小限パッケージリスト。
  githubRunnerPackagesMinimal = githubActionsRunnerPackages.minimal ++ selfHostRunnerPackages;
  # TypeScriptコードをビルドしてGitHub Actionsで利用できるようにします。
  # 吐き出されるコードはピュアなJavaScriptなのでアーキテクチャ非依存です。
  dotfiles-github-runner = pkgs.buildNpmPackage {
    pname = "dotfiles-github-runner";
    version = "0.0.0";
    src = ./.;
    npmDeps = pkgs.importNpmLock { npmRoot = ./.; };
    inherit (pkgs.importNpmLock) npmConfigHook;
    dontNpmInstall = true;
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
  # GitHub Actionsランナーはホストのnixデーモンと通信するため、
  # 統一されたユーザ値を使います。
  user = config.containerUsers.github-runner;
  # ユーザーとグループ定義。
  # コンテナのnixコマンドはホストのnixデーモンと通信するため、
  # UIDとGIDはホストと一致させる必要があります。
  # なので明示的に定義します。
  # ホスト側でユーザーを解決できなければ`trusted-users`が機能しません。
  users = {
    users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
      inherit (user) uid;
    };
    groups.github-runner.gid = user.gid;
  };
in
{
  # 共有定義を他のランナーモジュールから利用可能にします。
  _module.args.githubRunnerShare = {
    inherit
      githubRunnerPackagesAll
      githubRunnerPackagesMinimal
      dotfiles-github-runner
      users
      ;
  };

  # ホストのnixデーモンがコンテナ内のgithub-runnerユーザーを信頼するよう設定します。
  inherit users;
  nix.settings.trusted-users = [ "github-runner" ];

  sops.secrets."github-runner/dotfiles" = {
    sopsFile = ../../../../secrets/seminar/github-runner/dotfiles.yaml;
    key = "pat";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
