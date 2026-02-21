{
  lib,
  config,
  githubRunnerShare,
  ...
}:
let
  inherit (githubRunnerShare) users githubRunnerPackagesAll job-started-hook;
  addr = config.machineAddresses.github-runner-x64;
in
{
  containers.github-runner-x64 = {
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
          github-runners.dotfiles-x64 = {
            enable = true;
            ephemeral = true;
            replace = true;
            user = "github-runner";
            group = "github-runner";
            extraLabels = [ "NixOS" ];
            extraPackages = githubRunnerPackagesAll;
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
    network.networks."20-github-runner-x64-veth" = {
      # Linuxのインターフェース名はIFNAMSIZ(15文字)制限があるため、
      # 実際のインターフェース名は`ve-github-rRhHH`のように短縮されます。
      # しかしsystemd-networkdのmatchConfig.Nameはaltname(代替名)もマッチするため、
      # コンテナ名から生成される完全な名前で正しくマッチします。
      matchConfig.Name = "ve-github-runner-x64";
      addresses = [
        { Address = "${addr.host}/32"; }
      ];
      routes = [
        { Destination = "${addr.guest}/32"; }
      ];
    };

    services."container@github-runner-x64" = {
      # NixOSコンテナモジュールが生成するpostStartは`ip addr add`/`ip route add`を使うため、
      # systemd-networkdが先に設定済みの場合にEEXISTエラーで失敗します。
      # 冪等にするために`2>/dev/null || true`を付けます。
      # 実際の設定はsystemd-networkdに任せるため、postStartの内容が失敗していても問題ありません。
      postStart = lib.mkForce ''
        ifaceHost=ve-$INSTANCE
        ip link set dev "$ifaceHost" up
        ip addr add ${addr.host} dev "$ifaceHost" 2>/dev/null || true
        ip route add ${addr.guest} dev "$ifaceHost" 2>/dev/null || true
      '';
      serviceConfig = {
        # CIジョブがホストのリソースを過剰に消費しないよう制限します。
        # CPUQuotaはコア数×100%で指定するため、12スレッド×95%=1140%です。
        CPUQuota = "1140%";
        MemoryMax = "32G";
      };
    };
  };
}
