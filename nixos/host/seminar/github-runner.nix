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
  # コンテナ起動直後はsystemd-resolvedが準備完了していてもDNS解決できないことがある。
  # 実際にDNS解決が可能になるまでポーリングして待機する。
  wait-for-dns = pkgs.writeShellApplication {
    name = "wait-for-dns";
    runtimeInputs = [ pkgs.getent ];
    text = ''
      for _ in $(seq 1 30); do
        if getent hosts api.github.com > /dev/null 2>&1; then
          echo "DNS resolution is available."
          exit 0
        fi
        echo "Waiting for DNS resolution..."
        sleep 1
      done
      echo "ERROR: DNS resolution not available after 30 seconds" >&2
      exit 1
    '';
  };
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
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        # privateNetworkではDHCPによるDNS設定がないため明示的に指定
        networking.nameservers = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
          "8.8.4.4"
        ];
        # Allow incoming connections from host via private network.
        networking.firewall.trustedInterfaces = [ "eth0" ];
        # コンテナ起動直後のDNS未準備でrunner登録が失敗するのを防ぐ
        systemd.services.wait-for-dns = {
          description = "Wait for DNS resolution to become available";
          wantedBy = [ "github-runner-seminar-dotfiles-x64.service" ];
          before = [ "github-runner-seminar-dotfiles-x64.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${wait-for-dns}/bin/wait-for-dns";
          };
        };
        services.github-runners.seminar-dotfiles-x64 = {
          enable = true;
          ephemeral = true;
          replace = true;
          extraPackages = githubActionsRunnerPackages;
          tokenFile = "/etc/github-runner-dotfiles-token";
          url = "https://github.com/ncaq/dotfiles";
          extraEnvironment = {
            ACTIONS_RUNNER_HOOK_JOB_STARTED = "${job-started-hook}/bin/github-runner-job-started-hook";
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
