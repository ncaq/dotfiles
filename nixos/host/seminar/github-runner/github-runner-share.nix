{ pkgs, config, ... }:
let
  # GitHub Actionsのホステッドランナーをある程度互換しているパッケージリスト。
  githubActionsRunnerPackages = import ../../../../lib/github-actions-runner-packages.nix;
  # GitHubの標準ランナーにはないけれど個人的に含まれていて欲しいパッケージリスト。
  selfHostRunnerPackages =
    { pkgs, ... }:
    with pkgs;
    [
      cachix
    ];
  # GitHub Actionsランナーの並列数。
  # PRが複数ある場合はもちろん、
  # オプショナルであるビルドを飛ばしてマージしたときなどはたくさんのジョブが走ります。
  # コンテナや仮想マシンでリソースを制限しているため、
  # 複数立ち上げてもサーバのリソース量が破綻する心配はあまりありません。
  # またNixを使っている今のワークロードは殆どはIO待ちなので、
  # コンカレントに処理させたほうが効率的です。
  # このサーバのCPUの物理コア数と合わせています。
  # ARM64ランナーはQEMU TCGモードで動作するため、
  # .NETランタイムの同時起動数が多すぎるとメモリ不足で登録に失敗します。
  # ARM64でも安定して全ランナーが登録できる数に抑えています。
  runnerNum = 6;
  # runnerが使うTypeScriptコードをビルドしてGitHub Actionsで利用できるようにします。
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
  # CI用のnix設定。
  # ホストの`nix.settings`をベースにしますが、
  # キャッシュ設定などはCIの設定側で設定するべきなのと、
  # ホスト側のビルドフックは動かないので、
  # 必要な設定だけを抜き出します。
  ciNixSettings = {
    inherit (config.nix.settings) experimental-features;
    inherit (config.nix.settings) cores;
    inherit (config.nix.settings) max-jobs;
    inherit (config.nix.settings) accept-flake-config;
    inherit (config.nix.settings) trusted-users;
  };
in
{
  # 共有定義を他のランナーモジュールから利用可能にします。
  _module.args.githubRunnerShare = {
    inherit
      githubActionsRunnerPackages
      selfHostRunnerPackages
      runnerNum
      dotfiles-github-runner
      users
      ciNixSettings
      ;
  };

  # ホストのnixデーモンがコンテナ内のgithub-runnerユーザーを信頼するよう設定します。
  inherit users;
  nix.settings.trusted-users = [ "github-runner" ];

  sops.secrets."github-runner" = {
    sopsFile = ../../../../secrets/seminar/github-runner.yaml;
    key = "pat";
    owner = "github-runner";
    group = "github-runner";
    mode = "0400";
  };
}
