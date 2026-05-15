{
  pkgs,
  lib,
  config,
  githubRunnerShare,
  ...
}:
let
  inherit (githubRunnerShare)
    githubActionsRunnerPackages
    selfHostRunnerPackages
    runnerNum
    dotfiles-github-runner
    users
    ciNixSettings
    ;
  addr = config.machineAddresses.github-runner-x64;
in
{
  containers.github-runner-x64 = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "identity";
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/runner-registration-token" = {
        hostPath = config.sops.secrets."runner-registration-token".path;
        isReadOnly = true;
      };
      # ホストのnix-daemonがランナーのワークディレクトリ配下に書かれた、
      # `post-build-hook`を実行できるようにします。
      # Mic92/niks3-actionなどはhookのshimを、
      # `${RUNNER_TEMP}/niks3/`(= `/run/github-runner/<name>/_temp/niks3/`)に置き、
      # nixデーモンはホスト側からその絶対パスを開きます。
      # コンテナの`/run`tmpfsのままではホストからは見えないため、
      # 同一パスで両側から到達できるようにbind-mountを張ります。
      "/run/github-runner" = {
        hostPath = "/run/github-runner";
        isReadOnly = false;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        # NixデーモンにCI用の設定を渡します。
        # `trusted-users`などが含まれます。
        # コンテナはホストのnixデーモンソケットを共有するので、
        # ある程度設定を同期させる必要があります。
        inherit users;
        nix.settings = ciNixSettings;
        networking = {
          useHostResolvConf = lib.mkForce false;
          firewall.trustedInterfaces = [ "eth0" ]; # CIジョブ中にリッスンするため全許可
        };
        services = {
          resolved.enable = true;
          github-runners =
            let
              runnerNumbers = builtins.genList (x: x) runnerNum;
              args = { inherit pkgs; };
              extraPkgs = (githubActionsRunnerPackages args).all ++ selfHostRunnerPackages args;
              jobStartedHook = "${dotfiles-github-runner}/job-started-hook.js";
              mkRunnerDotfilesX64 = number: {
                name = "dotfiles-x64-${toString number}";
                value = {
                  enable = true;
                  ephemeral = true;
                  replace = true;
                  user = "github-runner";
                  group = "github-runner";
                  extraLabels = [ "NixOS" ];
                  extraPackages = extraPkgs;
                  tokenFile = "/etc/runner-registration-token";
                  url = "https://github.com/ncaq/dotfiles";
                  extraEnvironment.ACTIONS_RUNNER_HOOK_JOB_STARTED = jobStartedHook;
                };
              };
            in
            builtins.listToAttrs (map mkRunnerDotfilesX64 runnerNumbers);
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

    # bindMountsのhostPathは起動時に存在している必要があります。
    # `/run`はtmpfsで毎boot消えるため再生成します。
    # コンテナ内のgithub-runnerサービスは`User=github-runner`で起動し、
    # `WorkingDirectory=/run/github-runner/<name>`へchdirするため、
    # `github-runner`ユーザーが親ディレクトリをtraverseできる必要があります。
    # `privateUsers = "identity"`によりホストとコンテナのUIDは一致するため、
    # ホスト側のディレクトリ所有者を`github-runner`にしておけば、
    # コンテナ内のサービスも同ユーザーとしてアクセスできます。
    tmpfiles.rules = [
      "d /run/github-runner 0700 github-runner github-runner -"
    ];

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
        # CPUQuotaはコア数×100%で指定する必要があります。
        CPUQuota = "1000%"; # サーバが12スレッドなので、2スレッド引いた分を割り当てます。
        MemoryHigh = "16G"; # ソフトリミット。これを超えるとメモリを積極的に解放します。
        MemoryMax = "32G"; # ハードリミット。これぐらいで十分だろうという推定値。
      };
    };
  };
}
