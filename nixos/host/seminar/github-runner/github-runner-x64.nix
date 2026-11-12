{
  pkgs,
  lib,
  config,
  hardening,
  githubRunnerShare,
  ...
}:
let
  inherit (githubRunnerShare)
    githubActionsRunnerPackages
    selfHostRunnerPackages
    jobStartedHook
    registrationTokenBroker
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
  # 登録トークンを発行するホスト側のサービスの名前。
  tokenServiceOf = name: "${name}-registration-token";
  # 登録トークンを置くホスト側のディレクトリ。
  # サービスの`RuntimeDirectory`として作られます。
  tokenDirOf = name: "/run/${tokenServiceOf name}";
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
      hostAddress6 = addr.host6;
      localAddress6 = addr.guest6;
      bindMounts = {
        # ホスト側で発行した登録トークンの置き場所。
        # トークンはrenameで置き換えられるので、
        # ファイルではなくディレクトリをbind mountして更新が見えるようにします。
        "/run/runner-registration-token" = {
          hostPath = tokenDirOf name;
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
                    tokenFile = "/run/runner-registration-token/token";
                    # 登録トークンには`gh`で始まる接頭辞が無いので`auto`でも判定できますが、
                    # PATを渡していないことを明示します。
                    tokenType = "registration";
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

  # CIランナーの出口はインターネットだけ。
  #
  # ランナーの中ではリポジトリのワークフローが持ち込んだコードが動く。
  # 必要な通信先はGitHubやcache.nixos.orgで、
  # niks3-public.ncaq.netへのキャッシュの登録も、
  # コンテナの中では公開DNSで引いてCloudflare Tunnel経由で届く。
  # ホストのnix-daemonが行うsubstituteとpost-build-hookはホスト側の経路なので関係ない。
  #
  # 自宅LAN、tailnet、他のコンテナ(forgejoの2222のようにホストでDNATされる経路も含む)に、
  # CIジョブを触らせる理由は無い。
  local.machineEgress = lib.mapAttrs (_: _: { internet = true; }) runnerContainerDefs;

  systemd = lib.mkMerge (
    # ホスト側systemd-networkdでvethインターフェースにIPアドレスとルートを設定します。
    lib.mapAttrsToList (
      name: _:
      import ../../../../lib/container-veth.nix {
        inherit lib name;
        addr = addrOf name;
      }
    ) runnerContainerDefs
    ++ [
      {
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

        # 登録トークンは1時間で切れます。
        # ephemeralなランナーはジョブが終わるたびに登録し直すので、
        # 30分ごとに発行し直して、
        # 置いてあるトークンの残り時間が常に30分以上あるようにします。
        timers = lib.mapAttrs' (
          name: _:
          lib.nameValuePair (tokenServiceOf name) {
            wantedBy = [ "timers.target" ];
            # 発行に失敗した回があっても次の周期で試し直せるように、
            # 前回の起動からの経過ではなく時刻で起動します。
            timerConfig.OnCalendar = "*:0/30";
          }
        ) runnerContainerDefs;

        services =
          lib.mapAttrs' (
            name: def:
            lib.nameValuePair (tokenServiceOf name) {
              description = "Issue GitHub Actions runner registration token for ${name}";
              requires = [ "sops-install-secrets.service" ];
              after = [
                "sops-install-secrets.service"
                "network-online.target"
              ];
              wants = [ "network-online.target" ];
              # トークンをrootの所有で置くためにrootで動かします。
              # コンテナの中でこれを読むのはgithub-runnersモジュールのrootの処理だけです。
              serviceConfig = hardening.network // {
                Type = "oneshot";
                ExecStart = registrationTokenBroker;
                RuntimeDirectory = tokenServiceOf name;
                RuntimeDirectoryMode = "0700";
                # oneshotは終了すると停止扱いになるので、
                # 発行したトークンが消えないように残します。
                RuntimeDirectoryPreserve = true;
              };
              environment = {
                GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY = lib.removePrefix "https://github.com/" def.url;
                GITHUB_RUNNER_REGISTRATION_TOKEN_API = "https://api.github.com";
                GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE =
                  config.sops.secrets."runner-registration-pat".path;
              };
            }
          ) runnerContainerDefs
          // lib.mapAttrs' (
            name: _:
            lib.nameValuePair "container@${name}" {
              # bind mountするディレクトリと最初の登録トークンが、
              # コンテナの起動より前に用意されている必要があります。
              requires = [ "${tokenServiceOf name}.service" ];
              after = [ "${tokenServiceOf name}.service" ];
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
      }
    ]
  );
}
