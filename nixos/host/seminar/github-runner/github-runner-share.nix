{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # GitHub Actionsのホステッドランナーをある程度互換しているパッケージリスト。
  githubActionsRunnerPackages = import ../../../../lib/github-actions-runner-packages.nix;
  # GitHubの標準ランナーにはないけれど個人的に含まれていて欲しいパッケージリスト。
  selfHostRunnerPackages =
    { pkgs, ... }:
    with pkgs;
    [
      cachix
      inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
      # `./check.sh`はPATHにあるこのラッパーを使います。
      # メモリに合わせて評価のワーカー数を抑えるので、
      # 評価だけでメモリを食い尽くすのを防げます。
      (pkgs.callPackage ../../../../pkgs/nix-fast-build-wrapper.nix { })
    ];
  # runnerが使うTypeScriptコードをビルドしてGitHub Actionsで利用できるようにします。
  # 吐き出されるコードはピュアなJavaScriptなのでアーキテクチャ非依存です。
  github-runner = pkgs.buildNpmPackage {
    pname = "github-runner";
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
  # ジョブ開始フックを実行する`.sh`ラッパー。
  # `ACTIONS_RUNNER_HOOK_JOB_STARTED`に`.js`を直接指定すると、
  # github-runner 2.334.0では`.js`フックのセットアップが、
  # .NET由来のパスエラー("Second path fragment must not be a drive or UNC name")で失敗します。
  # GitHubが公式にサポートするフック形式は`.sh`と`.ps1`のみなので、
  # nixpkgsのnodeでjsを実行する`.sh`ラッパー経由で呼び出します。
  # これによりランナー内蔵nodeのパス解決にも依存しなくなります。
  jobStartedHook = lib.getExe (
    pkgs.writeShellApplication {
      name = "job-started-hook.sh";
      runtimeInputs = with pkgs; [ nodejs ];
      text = ''exec node ${github-runner}/job-started-hook.js "$@"'';
    }
  );
  # リポジトリの管理権限を持つPATで、
  # 1時間で切れるランナーの登録トークンを発行してファイルに置きます。
  # PATはホストのrootだけが持ち、
  # VMにはランナーの登録にしか使えない登録トークンだけを渡すための仲介です。
  # 環境変数の意味は、
  # `pkgs/github-runner-registration-token/src/GithubRunnerRegistrationToken/Config.hs`に書いてあります。
  registrationTokenBroker = lib.getExe (
    pkgs.callPackage ../../../../pkgs/github-runner-registration-token {
      inherit (inputs) himari-src;
    }
  );
  # ランナーのVMとホストで統一されたユーザ値を使います。
  user = config.serviceUser.github-runner;
  # ユーザーとグループ定義。
  # ランナーのVMは共有したホストのディレクトリへ書き込むことがあります。
  # virtiofsはUIDとGIDをそのまま通すので、
  # ホストの側の所有者と合うように明示的に定義します。
  users = {
    users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
      inherit (user) uid;
    };
    groups.github-runner.gid = user.gid;
  };
  # ランナーのVMの中のnix-daemonに渡すCI用のnix設定。
  # ホストの`nix.settings`をベースにしますが、
  # キャッシュ設定などはCIの設定側で設定するべきなのと、
  # ホスト側のビルドフックは動かないので、
  # 必要な設定だけを抜き出します。
  ciNixSettings = {
    inherit (config.nix.settings)
      experimental-features
      cores
      max-jobs
      accept-flake-config
      trusted-users
      ;
  };
in
{
  # 共有定義を他のランナーモジュールから利用可能にします。
  _module.args.githubRunnerShare = {
    inherit
      githubActionsRunnerPackages
      selfHostRunnerPackages
      jobStartedHook
      registrationTokenBroker
      users
      ciNixSettings
      ;
  };

  # ホストにも同じユーザーを置きます。
  # ランナーのVMと共有するディレクトリの所有者として使います。
  # ホストのnix-daemonの`trusted-users`には入れません。
  inherit users;

  sops = {
    secrets = {
      # ランナーの登録トークンを発行するためのPAT。
      # リポジトリの`Administration: Read and write`を持つfine-grained PATです。
      # ホストの`registrationTokenBroker`だけが読み、
      # コンテナには渡しません。
      "runner-registration-pat" = {
        sopsFile = ../../../../secrets/seminar/github-runner.yaml;
        # 暗号化したファイルのキーは、PATをコンテナへ渡していた頃の名前のままです。
        key = "runner-registration-token";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
