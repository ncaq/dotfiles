/**
  GitHub ActionsのセルフホステッドランナーをmicroVMで動かします。

  ランナーの中ではリポジトリのワークフローが持ち込んだコードが動きます。
  以前はNixOSコンテナで動かして、
  ホストのnix-daemonのソケットを共有していました。
  ランナーのユーザーはホストのnix-daemonの`trusted-users`で、
  これはホストのrootを渡すのと変わりません。
  VMの中にnix-daemonを持たせて、
  ホストのnix-daemonには触れさせないようにします。

  # ストア

  ホストの`/nix/store`を読み取り専用で共有して、
  VMだけが持つ書き込み用の層を重ねます。
  ファイルが見えているだけでは、
  VMのNixはホストのストアのパスを有効とは認めません。
  そのままだとホストに既にあるものをキャッシュから全て取り直すことになり、
  全ホストのビルドは100GiBを超える取得で40分かけても終わりませんでした。

  そこでVMの起動のたびに、
  ホストのNixのデータベースの写しをVMのデータベースとして渡します。
  VMのNixはホストのストアにあるパスをそのまま使えるので、
  取り直しも二重持ちも起きません。

  写した後にホストへ増えたパスは、
  VMからは見えないのでキャッシュから取るだけです。
  逆にホストがパスを消すと、
  VMのデータベースには有効なパスとして残るのに実体が無くなります。
  そのためホストのGCの間はVMを止めて、
  終わってから新しい写しで起動し直します。

  VMの中でGCを動かしてはいけません。
  VMのNixは書き込み用の層に「消した」という印を置くことしかできず、
  ホストのストアの大量のパスに印を付け続けて終わらなくなります。

  # 作り直し

  書き込み用の層とデータベースの写しは、
  VMを起動するたびに作り直します。
  VMは起動し直すまで使い回すので、
  ジョブをまたいで書き込み用の層のビルド結果が残ります。
  ジョブはVMの中のnix-daemonの`trusted-users`なので、
  後のジョブが使うストアを書き換えることはできます。
  守っているのはホストと他のVMで、
  同じVMの中のジョブ同士ではありません。
*/
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
  # リポジトリごとのランナーのVMの定義。
  # attr名がそのままVMの名前になります。
  # IPアドレスとvsockのCIDは`machineAddresses`と`microvmCid`の同名のエントリを参照するため、
  # VMを追加する時は`machine-mapping.nix`にも同名のエントリが必要です。
  runnerVmDefs = {
    github-runner-dotfiles-x64 = {
      basename = "dotfiles-x64";
      # コンテナの頃は評価だけがコンテナのメモリの制限に入り、
      # ビルドはホストのnix-daemonの側で動いていました。
      # VMでは評価もビルドもVMのメモリを使うので、
      # 同時に動かすジョブを絞ります。
      # ワークフローの側も`nvd-diff`の後に他のジョブを動かすので、
      # セルフホステッドランナーで同時に動くジョブは2つまでです。
      runnerNum = 2;
      url = "https://github.com/ncaq/dotfiles";
      # ホスト側のTAPインターフェイス名。
      # インターフェイス名は15文字までなので、VMの名前より短くします。
      tap = "vm-gh-dotfiles";
      mac = "02:00:00:00:00:41"; # 末尾バイトはゲストIPアドレスに対応
      vcpu = config.local.cpuBudgetThreads;
      # `./check.sh`だけで32GiBを使いました。
      # 24GiBでは`nix-eval-jobs`のワーカーがOOMで落ちました。
      mem = 40 * 1024;
    };
    github-runner-cdn-ncaq-net-x64 = {
      basename = "cdn-ncaq-net-x64";
      runnerNum = 1; # デプロイジョブは軽量なので1つで十分です。
      url = "https://github.com/ncaq/cdn.ncaq.net";
      tap = "vm-gh-cdn";
      mac = "02:00:00:00:00:51"; # 末尾バイトはゲストIPアドレスに対応
      vcpu = 4;
      mem = 8 * 1024;
      extraShares = [
        # cdn.ncaq.netのデプロイ先。
        # ランナー上のワークフローがrsyncで直接書き込みます(cdn.nix参照)。
        {
          tag = "cdn";
          source = "/mnt/noa/cdn.ncaq.net";
          mountPoint = "/mnt/noa/cdn.ncaq.net";
          proto = "virtiofs";
        }
      ];
      # github-runnersモジュールは`ProtectSystem=strict`でサービスを強化するため、
      # 共有が書き込み可能でも`ReadWritePaths`に含まれないパスへは書き込めません。
      extraRunnerOptions.serviceOverrides.ReadWritePaths = [ "/mnt/noa/cdn.ncaq.net" ];
    };
  };
  # 登録トークンを発行するホスト側のサービスの名前。
  tokenServiceOf = name: "${name}-registration-token";
  # 登録トークンを置くホスト側のディレクトリ。
  # サービスの`RuntimeDirectory`として作られます。
  tokenDirOf = name: "/run/${tokenServiceOf name}";
  # VMのストアを用意するホスト側のサービスの名前。
  storeServiceOf = name: "${name}-store";
  # ホストのNixのデータベースの写しを置くホスト側のディレクトリ。
  # サービスの`RuntimeDirectory`として作られます。
  storeDirOf = name: "/run/${storeServiceOf name}";
  # VMだけが持つ書き込み用の層のイメージ。
  overlayImage = "nix-store-overlay.img";
  overlayImageOf = name: "${config.microvm.stateDir}/${name}/${overlayImage}";
  # 書き込み用の層をVMの中でマウントする場所。
  overlayMount = "/nix/.rw-store";
  # ホストのNixのデータベース。
  hostNixDb = "/nix/var/nix/db";
  # VMの名前からmachineAddressesのエントリを引きます。
  addrOf = name: config.machineAddresses.${name};
  # GitHub ActionsのランナーのVMを生成する関数。
  mkRunnerVm =
    name:
    {
      # ランナー名の基礎となる名前。
      basename,
      # GitHub Actionsランナーの並列数。
      runnerNum,
      # リポジトリのURL。
      url,
      # ホスト側のTAPインターフェイス名。
      tap,
      # VMのNICのMACアドレス。
      mac,
      # VMに割り当てるCPUのスレッド数。
      vcpu,
      # VMのメモリ(MiB)。
      mem,
      # 追加の共有。
      extraShares ? [ ],
      # 各ランナー定義にマージする追加オプション。
      extraRunnerOptions ? { },
    }:
    let
      addr = addrOf name;
    in
    {
      inherit pkgs;
      config = {
        system.stateVersion = "26.05";
        microvm = {
          hypervisor = "cloud-hypervisor";
          vsock.cid = config.microvmCid.${name};
          inherit vcpu mem;
          # VMが使っていないメモリをホストへ返させます。
          # 返させないと、一度使ったメモリはVMが止まるまでホストに戻りません。
          balloon = true;
          interfaces = [
            {
              type = "tap";
              id = tap;
              inherit mac;
            }
          ];
          shares = [
            # ホストのストア。
            # virtiofsdはホストのrootで動くので、
            # 読み取り専用にしないとVMのrootからホストのストアを書き換えられます。
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
              readOnly = true;
            }
            # ホスト側で発行した登録トークンの置き場所。
            # トークンはrenameで置き換えられるので、
            # ファイルではなくディレクトリを共有して更新が見えるようにします。
            {
              tag = "token";
              source = tokenDirOf name;
              mountPoint = "/run/runner-registration-token";
              proto = "virtiofs";
              readOnly = true;
            }
            # ホストのNixのデータベースの写し。
            {
              tag = "nix-db";
              source = storeDirOf name;
              mountPoint = "/run/host-nix-db";
              proto = "virtiofs";
              readOnly = true;
            }
          ]
          ++ extraShares;
          # VMの中でビルドして取得したものは、VMだけが持つ書き込み用の層へ置きます。
          writableStoreOverlay = overlayMount;
          volumes = [
            {
              image = overlayImage;
              mountPoint = overlayMount;
              size = 100 * 1024;
            }
          ];
        };
        # NixOS TestのVMをネストした仮想化で動かします。
        boot.kernelModules = [ "kvm-amd" ];
        inherit users;
        nix.settings = ciNixSettings // {
          # ジョブは`flake.nix`のキャッシュの設定や`post-build-hook`を使います。
          # 信頼するのはVMの中のnix-daemonで、ホストのnix-daemonではありません。
          trusted-users = ciNixSettings.trusted-users ++ [ "github-runner" ];
          # ビルドの作業ディレクトリをルートのtmpfsではなくディスクに置いて、
          # メモリを評価とビルドのプロセスに残します。
          build-dir = "${overlayMount}/builds";
        };
        networking = {
          hostName = name;
          # CIジョブ中にリッスンするため全許可。
          # VMへ届く通信はホスト側で絞っています。
          firewall.enable = false;
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
        systemd = {
          tmpfiles.rules = [ "d ${overlayMount}/builds 0755 root root -" ];
          network.enable = true;
          network.networks."20-lan" = {
            matchConfig.Type = "ether";
            networkConfig = {
              Address = [
                "${addr.guest}/24"
                "${addr.guest6}/64"
              ];
              Gateway = [
                addr.host
                addr.host6
              ];
              DNS = [
                "1.1.1.1"
                "1.0.0.1"
                "8.8.8.8"
                "8.8.4.4"
                "2606:4700:4700::1111"
                "2606:4700:4700::1001"
                "2001:4860:4860::8888"
                "2001:4860:4860::8844"
              ];
            };
          };
          # ホストのNixのデータベースの写しを、VMのデータベースとして置きます。
          # nix-daemonが動き出す前に済ませる必要があるので、
          # ソケットより前に順序付けます。
          # ソケットは`basic.target`より前に起動するので、
          # 既定の依存関係を付けると順序が循環します。
          services.nix-db-seed = {
            description = "Seed Nix database from host";
            unitConfig.DefaultDependencies = false;
            after = [ "local-fs.target" ];
            before = [
              "nix-daemon.socket"
              "nix-daemon.service"
              "shutdown.target"
            ];
            conflicts = [ "shutdown.target" ];
            requiredBy = [
              "nix-daemon.socket"
              "nix-daemon.service"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = [
                # microvm.nixがVMのシステムの閉包だけを登録したデータベースを先に作っています。
                # ホストのデータベースにはその閉包も入っているので、丸ごと置き換えます。
                "${lib.getExe' pkgs.coreutils "rm"} --force ${hostNixDb}/db.sqlite-wal ${hostNixDb}/db.sqlite-shm"
                "${lib.getExe' pkgs.coreutils "install"} --mode=644 /run/host-nix-db/db.sqlite ${hostNixDb}/db.sqlite"
              ];
            };
          };
        };
      };
    };
  vmUnits = lib.mapAttrsToList (name: _: "microvm@${name}.service") runnerVmDefs;
  # 稼働中のsystemdと同じパッケージの`systemctl`。
  systemctl = lib.getExe' config.systemd.package "systemctl";
in
{
  microvm.vms = lib.mapAttrs mkRunnerVm runnerVmDefs;

  # CIランナーの出口はインターネットだけ。
  #
  # ランナーの中ではリポジトリのワークフローが持ち込んだコードが動く。
  # 必要な通信先はGitHubやcache.nixos.orgで、
  # niks3-public.ncaq.netへのキャッシュの登録も、
  # VMの中では公開DNSで引いてCloudflare Tunnel経由で届く。
  #
  # 自宅LAN、tailnet、他のコンテナ(forgejoの2222のようにホストでDNATされる経路も含む)に、
  # CIジョブを触らせる理由は無い。
  # TAPはコンテナのvethと違って名前を導けないので、VMの定義と同じ名前を明示する。
  local.machineEgress = lib.mapAttrs (_: def: {
    interface = def.tap;
    internet = true;
  }) runnerVmDefs;

  systemd = {
    # microvm.nixの推奨に従いsystemd-networkdでTAPインターフェースを設定します。
    network.networks = lib.mapAttrs' (
      name: def:
      let
        addr = addrOf name;
      in
      lib.nameValuePair "20-${def.tap}" {
        matchConfig.Name = def.tap;
        addresses = [
          { Address = "${addr.host}/32"; }
          { Address = "${addr.host6}/128"; }
        ];
        routes = [
          { Destination = "${addr.guest}/32"; }
          { Destination = "${addr.guest6}/128"; }
        ];
      }
    ) runnerVmDefs;

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
    ) runnerVmDefs;

    services = lib.mkMerge [
      (lib.mapAttrs' (
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
          # VMの中でこれを読むのはgithub-runnersモジュールのrootの処理だけです。
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
      ) runnerVmDefs)

      # VMを起動するたびに、書き込み用の層を捨てて、
      # ホストのNixのデータベースの写しを取り直します。
      # `RemainAfterExit`を付けないので、VMが起動し直されるたびにもう一度動きます。
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair (storeServiceOf name) {
          description = "Prepare Nix store for ${name}";
          # イメージを置くディレクトリはmicrovm.nixのこのサービスが作ります。
          requires = [ "install-microvm-${name}.service" ];
          after = [ "install-microvm-${name}.service" ];
          serviceConfig = hardening.isolated // {
            Type = "oneshot";
            ExecStart = [
              # イメージが無ければmicrovm.nixが起動の前に空のものを作ります。
              "${lib.getExe' pkgs.coreutils "rm"} --force ${overlayImageOf name}"
              # 動いているデータベースをそのままコピーすると書き込みの途中を拾うことがあるので、
              # SQLiteのバックアップの機能で一貫した状態を取ります。
              "${lib.getExe pkgs.sqlite} ${hostNixDb}/db.sqlite \".backup ${storeDirOf name}/db.sqlite\""
            ];
            RuntimeDirectory = storeServiceOf name;
            RuntimeDirectoryMode = "0700";
            # oneshotは終了すると停止扱いになるので、写しが消えないように残します。
            RuntimeDirectoryPreserve = true;
            # WALモードのデータベースは読むだけでも共有メモリのファイルへ書き込みます。
            ReadWritePaths = [
              hostNixDb
              "${config.microvm.stateDir}/${name}"
            ];
            # イメージとその親のディレクトリはmicrovmユーザーの所有なので、
            # rootでも所有者の検査を越える権限が無いと消せません。
            CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" ];
          };
        }
      ) runnerVmDefs)

      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair "microvm@${name}" {
          # `microvm@`はテンプレートなので、このVMの分だけを追加の設定として重ねます。
          overrideStrategy = "asDropin";
          # 共有するディレクトリと最初の登録トークン、データベースの写しが、
          # VMの起動より前に用意されている必要があります。
          requires = [
            "${tokenServiceOf name}.service"
            "${storeServiceOf name}.service"
          ];
          after = [
            "${tokenServiceOf name}.service"
            "${storeServiceOf name}.service"
          ];
        }
      ) runnerVmDefs)

      {
        # ホストのGCがパスを消すと、
        # VMのデータベースには有効なパスとして残るのに実体が無くなります。
        # GCの間はVMを止めて、終わってから新しい写しで起動し直します。
        # GCが失敗しても起動し直すように、止めた後の処理として書きます。
        nix-gc = {
          preStart = "${systemctl} stop ${lib.concatStringsSep " " vmUnits}";
          postStop = "${systemctl} start --no-block ${lib.concatStringsSep " " vmUnits}";
        };
      }
    ];
  };
}
