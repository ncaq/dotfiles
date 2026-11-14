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
  # ランナーのユーザーのUIDとGID。ホストとVMで同じ値です。
  runnerUser = config.serviceUser.github-runner;
  # cdn.ncaq.netのランナーへ共有するステージングのディレクトリ。
  cdnDeployRoot = config.local.cdnDeploy.deployRoot;
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
      # ワークフローの側は重い処理を1つのジョブにまとめて`nvd-diff`をその後に動かすので、
      # 1回の実行が同時に動かすジョブは1つです。
      # 2つあるのは、別のPRの実行と重なっても待たせないためです。
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
      # CIでNixOS TestのVMを動かします。
      nestedVirt = true;
      # ジョブの中でbubblewrapを動かせるように、
      # github-runnersモジュールが既定で付けるサービスの制限の一部を外します。
      #
      # `renovate-recovery`ワークフローのClaude Codeは、
      # 認証情報をコマンドに渡さないための隔離としてコマンドをbubblewrapの中で実行します。
      # bubblewrapは名前空間を作って`/proc`をマウントし直すので、
      # 以下の制限があると1つのコマンドも実行できません。
      # ランナーと同じ制限を付けた一時的なユニットで、1つずつ確かめました。
      #
      # - `RestrictNamespaces`: 名前空間を作れない
      # - `SystemCallFilter`の`~@mount`と`~capset`: bubblewrapがシグナルで落ちる
      # - `ProtectKernelLogs`と`ProtectKernelTunables`と`ProtectHostname`:
      #   `/proc`の一部を隠すので、新しい`/proc`のマウントをカーネルが拒否する
      #
      # ジョブをホストや他のVMから守るのはmicroVMの隔離で、
      # サービス単位の制限はVMの中での多層防御です。
      # 外すのはこのVMだけで、cdn.ncaq.netのランナーには手を付けません。
      extraRunnerOptions.serviceOverrides = {
        RestrictNamespaces = false;
        ProtectKernelLogs = false;
        ProtectKernelTunables = false;
        ProtectHostname = false;
        # モジュールは一覧を`mkBefore`で足すので、
        # 2つを除いた一覧で丸ごと置き換えます。
        SystemCallFilter = lib.mkForce [
          "~@clock"
          "~@cpu-emulation"
          "~@module"
          "~@obsolete"
          "~@raw-io"
          "~@reboot"
          "~setdomainname"
          "~sethostname"
        ];
      };
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
        # cdn.ncaq.netのデプロイのステージング。
        # ランナー上のワークフローがrsyncで書き込み、
        # ホストの同期のサービスが配信ディレクトリへ写します(cdn.nix参照)。
        #
        # virtiofsdはホストのrootで動いて、何も指定しないとUIDとGIDをそのまま通します。
        # ジョブはVMの中でrootになれるので、
        # そのままだとホストのファイルシステムにrootの所有でsetuidの実行ファイルを置けます。
        # VMの全てのUIDとGIDをホストの`github-runner`へ寄せて、
        # VMの誰が作ったファイルもホストでは`github-runner`の所有にします。
        # デバイスノードを作る権限もvirtiofsdから落とします。
        # VMの中のマウントに`nosuid`や`nodev`を付けても、
        # VMのrootが外せるのでホストは守れません。
        {
          tag = "cdn";
          source = cdnDeployRoot;
          mountPoint = cdnDeployRoot;
          proto = "virtiofs";
          # UIDとGIDの変換はPOSIX ACLと併用できません。
          posixAcl = false;
          extraArgs = [
            "--translate-uid=squash-guest:0:${toString runnerUser.uid}:4294967295"
            "--translate-gid=squash-guest:0:${toString runnerUser.gid}:4294967295"
            "--modcaps=-mknod"
          ];
        }
      ];
      # github-runnersモジュールは`ProtectSystem=strict`でサービスを強化するため、
      # 共有が書き込み可能でも`ReadWritePaths`に含まれないパスへは書き込めません。
      extraRunnerOptions.serviceOverrides.ReadWritePaths = [ cdnDeployRoot ];
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
  # サービスの`CacheDirectory`として作られます。
  # 写しは数百MiBあるので、tmpfsの`/run`ではなくディスクに置いてホストのメモリを使わせません。
  storeDirOf = name: "/var/cache/${storeServiceOf name}";
  # VMだけが持つ書き込み用の層のイメージ。
  overlayImage = "nix-store-overlay.img";
  overlayImageOf = name: "${config.microvm.stateDir}/${name}/${overlayImage}";
  # 書き込み用の層をVMの中でマウントする場所。
  overlayMount = "/nix/.rw-store";
  # Nixのデータベースの置き場所。ホストでもVMの中でも同じパスです。
  nixDbDir = "/nix/var/nix/db";
  # TAPのホスト側とゲスト側のネットワークの定義。
  # アドレスはVMの名前で`machineAddresses`のエントリを引きます。
  tapNetworkOf =
    name: tap:
    import ../../../../lib/microvm-tap.nix {
      inherit tap;
      addr = config.machineAddresses.${name};
    };
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
      # VMの中でさらにVMを動かせるようにするか。
      # ネストした仮想化はホストのKVMの攻撃面を広げるので、必要なVMだけで有効にします。
      nestedVirt ? false,
      # 追加の共有。
      extraShares ? [ ],
      # 各ランナー定義にマージする追加オプション。
      extraRunnerOptions ? { },
    }:
    {
      inherit pkgs;
      config = {
        system.stateVersion = "26.05";
        microvm = {
          hypervisor = "cloud-hypervisor";
          vsock.cid = config.microvmCid.${name};
          inherit vcpu mem;
          # cloud-hypervisorは何も指定しないとネストした仮想化をVMへ見せます。
          # モジュールを読み込まないだけではVMのrootが自分で読み込めるので、
          # 要らないVMではハイパーバイザの側で見せないようにします。
          cloud-hypervisor.extraArgs = lib.optionals (!nestedVirt) [
            "--cpus"
            "nested=off"
          ];
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
        # ホストと同じCPUなので、読み込むモジュールはホストの設定から導きます。
        boot.kernelModules = lib.optionals nestedVirt (
          lib.filter (lib.hasPrefix "kvm-") config.boot.kernelModules
        );
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
                  extraEnvironment = {
                    ACTIONS_RUNNER_HOOK_JOB_STARTED = jobStartedHook;
                    # 同じVMで`./check.sh`が重なり得る数。
                    # `nix-fast-build`のラッパーが、評価に使うメモリの予算をこの数で割ります。
                    NIX_FAST_BUILD_CONCURRENT_JOBS = toString runnerNum;
                  };
                }
                // extraRunnerOptions;
              };
            in
            builtins.listToAttrs (map mkRunner runnerNumbers);
        };
        systemd = {
          tmpfiles.rules = [ "d ${overlayMount}/builds 0755 root root -" ];
          network = (tapNetworkOf name tap).guest;
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
                "${lib.getExe' pkgs.coreutils "rm"} --force ${nixDbDir}/db.sqlite-wal ${nixDbDir}/db.sqlite-shm"
                "${lib.getExe' pkgs.coreutils "install"} --mode=644 /run/host-nix-db/db.sqlite ${nixDbDir}/db.sqlite"
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

  # ブートテストがストアの準備とGCの前後の処理を確かめるために読みます。
  local.githubRunnerVms = lib.mapAttrs (name: _: {
    storeService = "${storeServiceOf name}.service";
    storeDatabase = "${storeDirOf name}/db.sqlite";
    overlayImage = overlayImageOf name;
  }) runnerVmDefs;

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
    network.networks = lib.mkMerge (
      lib.mapAttrsToList (name: def: (tapNetworkOf name def.tap).host) runnerVmDefs
    );

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
              # 前の起動の時の写しも捨てます。
              "${lib.getExe' pkgs.coreutils "rm"} --force ${overlayImageOf name} ${storeDirOf name}/db.sqlite"
              # 動いているデータベースをそのままコピーすると書き込みの途中を拾うことがあるので、
              # SQLiteのバックアップの機能で一貫した状態を取ります。
              "${lib.getExe pkgs.sqlite} ${nixDbDir}/db.sqlite \".backup ${storeDirOf name}/db.sqlite\""
            ];
            CacheDirectory = storeServiceOf name;
            CacheDirectoryMode = "0700";
            # WALモードのデータベースは読むだけでも共有メモリのファイルへ書き込みます。
            ReadWritePaths = [
              nixDbDir
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
