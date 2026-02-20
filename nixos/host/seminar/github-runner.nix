{
  pkgs,
  lib,
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
          useHostResolvConf = lib.mkForce false;
          # ネットワーク通信の受け入れを許可します。
          firewall.trustedInterfaces = [ "eth0" ];
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

  systemd = {
    # ホスト側systemd-networkdでvethインターフェースにIPアドレスとルートを設定します。
    # NixOSコンテナモジュールのExecStartPostはコンテナのdefault target到達後に実行されるため、
    # github-runnerサービスの起動時にはまだホスト側のネットワーク設定が完了していません。
    # github-runnerサービスの起動にはネットワークが必要なためデッドロックしてしまいます。
    # systemd-networkdはvethインターフェース作成直後に設定を適用するため、
    # コンテナ内のサービスが起動する前にネットワークが使用可能になります。
    network.networks."20-github-runner-veth" = {
      # Linuxのインターフェース名はIFNAMSIZ(15文字)制限があるため、
      # 実際のインターフェース名は`ve-github-rRhHH`のように短縮されます。
      # しかしsystemd-networkdのmatchConfig.Nameはaltname(代替名)もマッチするため、
      # コンテナ名から生成される完全な名前で正しくマッチします。
      matchConfig.Name = "ve-github-runner-seminar-dotfiles-x64";
      addresses = [
        { Address = "${addr.host}/32"; }
      ];
      routes = [
        { Destination = "${addr.guest}/32"; }
      ];
    };

    # NixOSコンテナモジュールが生成するpostStartは`ip addr add`/`ip route add`を使うため、
    # systemd-networkdが先に設定済みの場合にEEXISTエラーで失敗します。
    # 冪等にするために`2>/dev/null || true`を付けます。
    services."container@github-runner-seminar-dotfiles-x64".postStart = lib.mkForce ''
      ifaceHost=ve-$INSTANCE
      ip link set dev "$ifaceHost" up
      ip addr add ${addr.host} dev "$ifaceHost" 2>/dev/null || true
      ip route add ${addr.guest} dev "$ifaceHost" 2>/dev/null || true
    '';
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
