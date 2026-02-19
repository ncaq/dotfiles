{
  pkgs,
  config,
  ...
}:
let
  # GitHub Actionsの標準イメージ互換リストに個人的に欲しいパッケージを足します。
  githubActionsRunnerPackages =
    (import ../../../lib/github-actions-runner-packages.nix {
      inherit pkgs;
    }).all
    ++ (with pkgs; [
      attic-client
      cachix
    ]);
  addr = config.machineAddresses.github-runner-seminar-dotfiles-x64;
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
  # ジョブ開始前に信頼できないPRを拒否するフックスクリプト。
  # ワークフロー側のif条件が迂回された場合でもランナー側で防御する。
  # 多重防御の一環。
  job-started-hook = pkgs.writeShellApplication {
    name = "github-runner-job-started-hook.sh";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      echo "Job started hook: event=$GITHUB_EVENT_NAME actor=$GITHUB_ACTOR"

      # push, merge_group, workflow_dispatchなどはリポジトリへの書き込み権限が必要なため許可
      if [[ "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "pull_request_target" ]]; then
        echo "Event '$GITHUB_EVENT_NAME' is allowed."
        exit 0
      fi

      # PRイベントの場合、作者がリポジトリオーナーか確認
      author_association=$(jq -r '.pull_request.author_association // "UNKNOWN"' "$GITHUB_EVENT_PATH")
      sender=$(jq -r '.sender.login // "UNKNOWN"' "$GITHUB_EVENT_PATH")
      echo "PR author_association=$author_association sender=$sender"

      if [[ "$author_association" == "OWNER" ]]; then
        echo "PR author is OWNER, allowed."
        exit 0
      fi

      echo "ERROR: Untrusted PR (author_association=$author_association, sender=$sender). Rejecting job."
      exit 1
    '';
  };
in
{
  containers.github-runner-seminar-dotfiles-x64 = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/github-runner-dotfiles-token" = {
        hostPath = config.sops.secrets."github-runner/dotfiles".path;
        isReadOnly = true;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        # ホストの評価済みnix.settingsを継承します。
        # trusted-usersなどホスト側で追加された設定も含まれます。
        # コンテナはホストのnixデーモンソケットを共有しますが、
        # cachixなどのツールはローカルのnix.confを参照するため
        # コンテナ側にも同じ設定が必要です。
        inherit users;
        nix.settings = config.nix.settings;
        networking = {
          # systemd-resolvedを使うため、ホストのresolv.confは使わずにコンテナ内で解決させるようにします。
          useHostResolvConf = lib.mkForce false;
          # ネットワーク通信の受け入れを許可します。
          firewall.trustedInterfaces = [ "eth0" ];
        };
        systemd = {
          network.enable = true;
          network.networks."20-lan" = {
            matchConfig.Type = "ether";
            networkConfig = {
              Address = "${addr.guest}/24";
              Gateway = addr.host;
              DNS = [
                "1.1.1.1"
                "1.0.0.1"
                "8.8.8.8"
                "8.8.4.4"
              ];
            };
          };
        };
        services = {
          resolved.enable = true;
          github-runners.seminar-dotfiles-x64 = {
            enable = true;
            ephemeral = true;
            replace = true;
            user = "github-runner";
            group = "github-runner";
            extraLabels = [ "NixOS" ];
            extraPackages = githubActionsRunnerPackages;
            tokenFile = "/etc/github-runner-dotfiles-token";
            url = "https://github.com/ncaq/dotfiles";
            extraEnvironment = {
              ACTIONS_RUNNER_HOOK_JOB_STARTED = "${job-started-hook}/bin/github-runner-job-started-hook.sh";
            };
          };
        };
      };
  };

  # ホストのnixデーモンがコンテナ内のgithub-runnerユーザーを信頼するよう設定します。
  inherit users;
  nix.settings.trusted-users = [ "github-runner" ];

  sops.secrets."github-runner/dotfiles" = {
    sopsFile = ../../../secrets/seminar/github-runner/dotfiles.yaml;
    key = "pat";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
