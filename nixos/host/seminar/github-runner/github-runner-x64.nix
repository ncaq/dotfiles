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
    jobStartedHook
    users
    ciNixSettings
    ;
  # リポジトリごとのランナーコンテナ定義。
  # attr名がそのままコンテナ名になります。
  # IPアドレスはmachineAddressesの同名エントリを参照するため、
  # コンテナを追加する時はmachine-mapping.nixにも同名のエントリが必要です。
  runnerContainerDefs = {
    github-runner-dotfiles-x64 = {
      basename = "dotfiles-x64";
      runnerNum = 5;
      url = "https://github.com/ncaq/dotfiles";
    };
    github-runner-cdn-ncaq-net-x64 = {
      basename = "cdn-ncaq-net-x64";
      runnerNum = 1; # デプロイジョブは軽量なので1つで十分です。
      url = "https://github.com/ncaq/cdn.ncaq.net";
      extraBindMounts = {
        # cdn.ncaq.netのデプロイ先。
        # ランナー上のワークフローがrsyncで直接書き込みます(cdn.nix参照)。
        "/mnt/noa/cdn.ncaq.net" = {
          hostPath = "/mnt/noa/cdn.ncaq.net";
          isReadOnly = false;
        };
      };
      # github-runnersモジュールは`ProtectSystem=strict`でサービスを強化するため、
      # bind mountがrwでも`ReadWritePaths`に含まれないパスへは書き込めません。
      extraRunnerOptions.serviceOverrides.ReadWritePaths = [ "/mnt/noa/cdn.ncaq.net" ];
    };
  };
  # コンテナ名からmachineAddressesのエントリを引きます。
  addrOf = name: config.machineAddresses.${name};
  # GitHub Actionsランナーコンテナを生成する関数。
  mkRunnerContainer =
    name:
    {
      # ランナー名の基礎となる名前。
      basename,
      # GitHub Actionsランナーの並列数。
      # 上位レベルでリソースを制限しているため、
      # 複数立ち上げてもサーバの全体のリソース量が破綻する心配はあまりありません。
      # あまりCPUを使い切れなくても、
      # Nixが動く時は大抵はキャッシュダウンロードのIO待ちなので、
      # 並列に動作出来るならした方が効率的です。
      runnerNum,
      # リポジトリのURL。
      url,
      # 追加のbind-mounts。
      extraBindMounts ? { },
      # 各ランナー定義にマージする追加オプション。
      extraRunnerOptions ? { },
    }:
    let
      addr = addrOf name;
    in
    {
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
      }
      // extraBindMounts;
      config =
        { lib, ... }:
        {
          system.stateVersion = "26.05";
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
                mkRunner = number: {
                  name = "${basename}-${toString number}";
                  value = {
                    enable = true;
                    ephemeral = true;
                    replace = true;
                    user = "github-runner";
                    group = "github-runner";
                    extraLabels = [ "NixOS" ];
                    extraPackages = extraPkgs;
                    tokenFile = "/etc/runner-registration-token";
                    inherit url;
                    extraEnvironment.ACTIONS_RUNNER_HOOK_JOB_STARTED = jobStartedHook;
                  }
                  // extraRunnerOptions;
                };
              in
              builtins.listToAttrs (map mkRunner runnerNumbers);
          };
        };
    };
in
{
  containers = lib.mapAttrs mkRunnerContainer runnerContainerDefs;

  systemd = {
    # ホスト側systemd-networkdでvethインターフェースにIPアドレスとルートを設定します。
    # NixOSコンテナモジュールのExecStartPostはコンテナのdefault target到達後に実行されるため、
    # github-runnerサービスの起動時にはまだホスト側のネットワーク設定が完了していません。
    # github-runnerサービスの起動にはネットワークが必要なためデッドロックしてしまいます。
    # systemd-networkdはvethインターフェース作成直後に設定を適用するため、
    # コンテナ内のサービスが起動する前にネットワークが使用可能になります。
    network.networks = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "20-${name}-veth" {
        # Linuxのインターフェース名はIFNAMSIZ(15文字)制限があるため、
        # 実際のインターフェース名は`ve-github-rRhHH`のように短縮されます。
        # しかしsystemd-networkdのmatchConfig.Nameはaltname(代替名)もマッチするため、
        # コンテナ名から生成される完全な名前で正しくマッチします。
        matchConfig.Name = "ve-${name}";
        addresses = [
          { Address = "${(addrOf name).host}/32"; }
        ];
        routes = [
          { Destination = "${(addrOf name).guest}/32"; }
        ];
      }
    ) runnerContainerDefs;

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

    services = lib.mapAttrs' (
      name: _:
      let
        addr = addrOf name;
      in
      lib.nameValuePair "container@${name}" {
        # NixOSコンテナモジュールが生成するpostStartは`ip addr add`/`ip route add`を使うため、
        # systemd-networkdが先に設定済みの場合にEEXISTエラーで失敗します。
        # 冪等にするために`2>/dev/null || true`を付けます。
        # 実際の設定はsystemd-networkdに任せるため、
        # postStartの内容が失敗していても問題ありません。
        postStart = lib.mkForce ''
          ifaceHost=ve-$INSTANCE
          ip link set dev "$ifaceHost" up
          ip addr add ${addr.host} dev "$ifaceHost" 2>/dev/null || true
          ip route add ${addr.guest} dev "$ifaceHost" 2>/dev/null || true
        '';
        serviceConfig = {
          # CIジョブがホストのリソースを過剰に消費しないよう制限します。
          # CPUQuotaはコア数×100%で指定する必要があります。
          # 割り当て可能スレッド数分を割り当てます。
          CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
          MemoryHigh = "16G"; # ソフトリミット。これを超えるとメモリを積極的に解放します。
          MemoryMax = "32G"; # ハードリミット。これぐらいで十分だろうという推定値。
        };
      }
    ) runnerContainerDefs;
  };
}
