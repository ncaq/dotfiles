{
  pkgs,
  config,
  ...
}:
let
  githubActionsRunnerPackages =
    (import ../../../lib/github-actions-runner-packages.nix {
      inherit pkgs;
    }).all;
  addr = config.machineAddresses.github-runner-seminar-dotfiles-x64;
  # ジョブ開始前に信頼できないPRを拒否するフックスクリプト。
  # ワークフロー側のif条件が迂回された場合でもランナー側で防御する。
  # 多重防御の一環。
  job-started-hook = pkgs.writeShellApplication {
    name = "github-runner-job-started-hook";
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
        # ホストの基本的なNix設定を継承します。
        nix.settings = (import ../../core/nix-settings.nix { }).nix.settings;
        networking = {
          useHostResolvConf = lib.mkForce false;
          # privateNetworkではDHCPによるDNS設定がないため明示的に指定
          nameservers = [
            "1.1.1.1"
            "1.0.0.1"
            "8.8.8.8"
            "8.8.4.4"
          ];
          # ネットワーク通信の受け入れを許可します。
          firewall.trustedInterfaces = [ "eth0" ];
        };
        # コンテナ起動直後はネットワークが一時的に使えずrunner登録が失敗することがあるため、
        # 失敗しても再起動するようにします。
        systemd.services.github-runner-seminar-dotfiles-x64.serviceConfig = {
          Restart = lib.mkForce "always"; # デフォルトでは成功時のみに再起動になっているので失敗時含めて常に再起動。
          RestartSec = 5;
        };
        services = {
          resolved.enable = true;
          github-runners.seminar-dotfiles-x64 = {
            enable = true;
            ephemeral = true;
            replace = true;
            extraLabels = [ "NixOS" ];
            extraPackages = githubActionsRunnerPackages;
            tokenFile = "/etc/github-runner-dotfiles-token";
            url = "https://github.com/ncaq/dotfiles";
            extraEnvironment = {
              ACTIONS_RUNNER_HOOK_JOB_STARTED = "${job-started-hook}/bin/github-runner-job-started-hook";
            };
          };
        };
      };
  };

  sops.secrets."github-runner/dotfiles" = {
    sopsFile = ../../../secrets/seminar/github-runner/dotfiles.yaml;
    key = "pat";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
