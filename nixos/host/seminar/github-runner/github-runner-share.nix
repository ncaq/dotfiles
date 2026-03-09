{ pkgs, config, ... }:
let
  # GitHub Actionsのホステッドランナーをある程度互換しているパッケージリスト。
  githubActionsRunnerPackages = import ../../../../lib/github-actions-runner-packages.nix;
  # GitHubの標準ランナーにはないけれど個人的に含まれていて欲しいパッケージリスト。
  selfHostRunnerPackages =
    { pkgs, ... }:
    with pkgs;
    [
      attic-client
      cachix
    ];
  # GitHub Actionsランナーの並列数。
  # PRが複数ある場合はもちろん、
  # オプショナルであるビルドを飛ばしてマージしたときなどはたくさんのジョブが走ります。
  # コンテナや仮想マシンでリソースを制限しているため、
  # 複数立ち上げてもサーバのリソース量が破綻する心配はあまりありません。
  # またNixを使っている今のワークロードは殆どはIO待ちなので、
  # コンカレントに処理させたほうが効率的です。
  # とりあえずこのサーバのCPUの論理コア数と合わせています。
  # コンテナや仮想マシンのリミットよりも多いですが前述の理由でIO待ちを効率的に処理するためです。
  runnerNum = 12;
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
