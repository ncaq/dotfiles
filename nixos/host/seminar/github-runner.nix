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
        tsc github-runner-job-started-hook.ts --strict --target ES2020 --module node16 --moduleResolution node16 --skipLibCheck --outDir $out/bin
      '';
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
              ACTIONS_RUNNER_HOOK_JOB_STARTED = "${job-started-hook}/bin/github-runner-job-started-hook.js";
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
