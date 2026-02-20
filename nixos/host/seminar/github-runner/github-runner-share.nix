{ config, pkgs, ... }:
let
  # GitHub Actionsの標準イメージ互換リストに個人的に欲しいパッケージを足します。
  githubRunnerPackages =
    (import ../../../../lib/github-actions-runner-packages.nix {
      inherit pkgs;
    }).all
    ++ (with pkgs; [
      attic-client
      cachix
    ]);
  # ジョブ開始前に信頼できないPRを拒否するフックスクリプト。
  # ワークフロー側のif条件が迂回された場合でもランナー側で防御する。
  # 多重防御の一環。
  types-node = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@types/node/-/node-22.15.3.tgz";
    hash = "sha256-n1pXwQvnwi0XxxtgWtPWm6+7uhiOUm5X3layHMWpFYI=";
  };
  job-started-hook =
    pkgs.runCommand "github-runner-job-started-hook"
      {
        nativeBuildInputs = [ pkgs.typescript ];
      }
      ''
        mkdir -p node_modules/@types/node $out/bin
        tar xzf ${types-node} -C node_modules/@types/node --strip-components=1
        cp ${./github-runner-job-started-hook.ts} github-runner-job-started-hook.ts
        tsc --strict --target ES2023 --module node16 --moduleResolution node16 --skipLibCheck --outDir $out/bin \
          github-runner-job-started-hook.ts
      '';
  # GitHub Actionsランナーはホストのnixデーモンと通信するため、ユーザーとグループを明示的に定義します。
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
  _module.args.githubRunnerShared = {
    inherit githubRunnerPackages job-started-hook users;
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
