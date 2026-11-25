/**
  GitHub ActionsのセルフホステッドランナをmicroVMで動かします。

  ランナの中ではリポジトリのワークフローが持ち込んだコードが動きます。
  以前はNixOSコンテナで動かして、
  ホストのnix-daemonのソケットを共有していました。
  ランナのユーザはホストのnix-daemonの`trusted-users`で、
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
  ホストのストアの最適化も、
  VMが掴んでいるファイルをハードリンクへ置き換えるので、
  同じようにVMを止めている間に動かします。
  GCと最適化は毎日続けて動き、
  負荷が高い日は見送られます。
  時刻と条件は`pkgs/nix-store-maintenance/module.nix`に書いています。

  VMの中でGCを動かしてはいけません。
  VMのNixは書き込み用の層に「消した」という印を置くことしかできず、
  ホストのストアの大量のパスに印を付け続けて終わらなくなります。

  # 作り直し

  書き込み用の層とデータベースの写しは、
  VMを起動するたびに作り直します。
  VMは起動し直すまで使い回すので、
  ジョブをまたいで書き込み用の層のビルド結果が残ります。
  VMの中ではGCできないので、
  層はVMを再起動すると空になります。
  ホストのGCと最適化が毎日VMを再起動するので、
  層を空にするためだけにVMを止める仕組みは持ちません。
  負荷が高くて見送られた日が続くと、その間は層が増え続けます。
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
  # ランナのユーザのUIDとGID。ホストとVMで同じ値です。
  runnerUser = config.serviceUser.github-runner;
  # cdn.ncaq.netのランナへ共有するステージングのディレクトリ。
  cdnDeployRoot = config.services.cdn-ncaq-net-sync.deployRoot;
  # リポジトリごとのランナのVMの定義。
  # attr名がそのままVMの名前になります。
  # IPアドレスとvsockのCIDは`machineAddresses`と`microvmCid`の同名のエントリを参照するため、
  # VMを追加する時は`machine-mapping.nix`にも同名のエントリが必要です。
  runnerVmDefs = {
    github-runner-dotfiles-x64 = {
      basename = "dotfiles-x64";
      # コンテナの頃は評価だけがコンテナのメモリの制限に入り、
      # ビルドはホストのnix-daemonの側で動いていました。
      # VMでは評価もビルドもVMのメモリを使うので、
      # 同時に動かすジョブを1つに絞ります。
      # ジョブが重なった時は後の方が待ちますが、
      # その代わりに1つのジョブがVMのメモリを全て評価のワーカに使えます。
      runnerNum = 1;
      url = "https://github.com/ncaq/dotfiles";
      # ホスト側のTAPインタフェース名。
      # インタフェース名は15文字までなので、VMの名前より短くします。
      tap = "vm-gh-dotfiles";
      mac = "02:00:00:00:00:41"; # 末尾バイトはゲストIPアドレスに対応
      vcpu = config.local.cpuBudgetThreads;
      # `./check.sh`が評価のワーカを4つにする大きさにしています。
      # `check.sh`はVMから見えるメモリの半分を、ワーカ1つあたりの3400MiBで割ります。
      # VMから見えるメモリはカーネルが自分で使う分だけ割り当てより1GiBほど減るので、
      # 32GiBを割り当てると31GiBほどになり、ワーカは4つです。
      #
      # ワーカ4つでの`ciJobs`の評価のピークは、実測で13GiBほどでした。
      # 残りは、評価の途中から動き出すビルドとブートテストのVMが使います。
      # ランナが2つでワーカも2つずつだった頃は、24GiBでは`nix-eval-jobs`のワーカがOOMで落ちました。
      mem = 32 * 1024;
      # CIでNixOS TestのVMを動かします。
      nestedVirt = true;
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
        # ランナ上のワークフローがrsyncで書き込み、
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
  # GitHubのAPIで使う`OWNER/REPO`の形のリポジトリ名。
  repositoryOf = def: lib.removePrefix "https://github.com/" def.url;
  # VMの中のランナがGitHubに登録される名前。
  runnerNamesOf =
    { basename, runnerNum, ... }:
    builtins.genList (number: "${basename}-${toString number}") runnerNum;
  # 登録トークンを発行するホスト側のサービスの名前。
  tokenServiceOf = name: "${name}-registration-token";
  # 登録トークンを置くホスト側のディレクトリ。
  # サービスの`RuntimeDirectory`として作られます。
  tokenDirOf = name: "/run/${tokenServiceOf name}";
  # VMのストアを用意するホスト側のサービスの名前と、
  # ホストのNixのデータベースの写しを置くホスト側のディレクトリ。
  # どちらも`pkgs/github-runner-store/module.nix`が決めます。
  storeServiceOf = name: config.services.github-runner-store.vms.${name}.unit;
  storeDirOf = name: config.services.github-runner-store.vms.${name}.storeDir;
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
  # GitHub ActionsのランナのVMを生成する関数。
  mkRunnerVm =
    name:
    {
      # ランナ名の基礎となる名前。
      basename,
      # GitHub Actionsランナの並列数。
      runnerNum,
      # リポジトリのURL。
      url,
      # ホスト側のTAPインタフェース名。
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
      # 各ランナ定義にマージする追加オプション。
      extraRunnerOptions ? { },
    }:
    {
      inherit pkgs;
      # 宣言的なmicroVMの既定はtrueで、
      # ゲストの構成が変わるたびに設定の適用でVMが再起動されて、
      # 実行中のジョブが落ちます。
      # 新しい構成の置き場所は設定の適用のたびに更新されるので、
      # VMを再起動した後から新しい構成になります。
      # 共有やTAPのようなホスト側のユニットに関わる変更をすぐ反映したい時は、
      # 手で`microvm@`を再起動します。
      restartIfChanged = false;
      config = {
        system.stateVersion = "26.05";
        microvm = {
          hypervisor = "cloud-hypervisor";
          vsock.cid = config.microvmCid.${name};
          inherit vcpu mem;
          # cloud-hypervisorは何も指定しないとネストした仮想化をVMへ見せます。
          # モジュールを読み込まないだけではVMのrootが自分で読み込めるので、
          # 要らないVMではハイパバイザの側で見せないようにします。
          cloud-hypervisor.extraArgs = lib.optionals (!nestedVirt) [
            "--cpus"
            "nested=off"
          ];
          # VMが使っていないメモリをホストへ返させます。
          # 返させないと、一度使ったメモリはVMが止まるまでホストに戻りません。
          # バルーンが返すのは空いているメモリだけで、
          # ファイルのキャッシュは使っているメモリとして残ります。
          # ジョブが終わった後にキャッシュを空ける処理は下の`reclaim-idle-memory`です。
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
              # nixpkgsを上げると全ホストのクロージャのほとんどがホストのストアに無いものになり、
              # 取得だけで40GiB近くになります。
              # さらにカーネルが上がると、
              # CPU最適化したホストごとのカーネルを並べてビルドする作業ディレクトリも、
              # この層に置かれます。
              # 前のジョブの結果が残った状態でlockの更新を1回走らせると、
              # 100GiBでは足りなくなりました。
              # イメージは起動のたびに作り直すので、ホストのディスクを使い続けることはありません。
              size = 200 * 1024;
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
              args = { inherit pkgs; };
              extraPkgs = (githubActionsRunnerPackages args).all ++ selfHostRunnerPackages args;
              mkRunner = runnerName: {
                name = runnerName;
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
                  };
                }
                // extraRunnerOptions;
              };
            in
            builtins.listToAttrs (
              map mkRunner (runnerNamesOf {
                inherit basename runnerNum;
              })
            );
        };
        systemd = {
          tmpfiles.rules = [ "d ${overlayMount}/builds 0755 root root -" ];
          network = (tapNetworkOf name tap).guest;
          services = {
            # ジョブが動いていない間、VMのメモリをホストへ返します。
            #
            # ジョブが読み書きしたファイルのキャッシュは、ジョブが終わってもVMのメモリに残ります。
            # バルーンのfree page reportingがホストへ返すのは空いているメモリだけなので、
            # そのままだとVMはジョブが無い間も十数GiBを持ち続けます。
            # キャッシュを捨てて空きメモリにすれば、バルーンがホストへ返します。
            #
            # 返すのは2MiB単位でまとまった空きだけなので、
            # 断片化した空きもまとめてから返させます。
            #
            # キャッシュを捨てても失うものは小さいです。
            # ストアの大半はホストからvirtiofsで読んでいて、ホストの側にもキャッシュがあります。
            reclaim-idle-memory = {
              description = "Return memory to the host while no job is running";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = lib.getExe (
                  pkgs.writeShellApplication {
                    name = "reclaim-idle-memory";
                    runtimeInputs = [
                      pkgs.coreutils
                      pkgs.procps
                    ];
                    text = ''
                      # ジョブの実行中はランナの`Runner.Listener`が子の`Runner.Worker`を持ちます。
                      # どちらもnixpkgsではラッパではない実行ファイルなので、
                      # プロセス名がそのまま実行ファイルの名前になり、`--exact`で一致します。
                      #
                      # ジョブは任意のコードを実行できるので、
                      # 名前だけで探すと、同じ名前のプロセスを残してジョブが動いているように見せられます。
                      # ジョブのプロセスは`Runner.Listener`の子にはなれないので、
                      # ランナのユーザの`Runner.Listener`の子だけを探します。
                      job_running() {
                        local listeners
                        # `Runner.Listener`が居なければ、ジョブも動いていません。
                        listeners=$(pgrep --exact --uid github-runner --delimiter , Runner.Listener) || return 1
                        pgrep --exact --uid github-runner --parent "$listeners" Runner.Worker >/dev/null
                      }
                      # 実行中にキャッシュを捨てるとビルドが遅くなるだけなので、何もしません。
                      if job_running; then
                        exit 0
                      fi
                      sync
                      echo 3 >/proc/sys/vm/drop_caches
                      echo 1 >/proc/sys/vm/compact_memory
                    '';
                  }
                );
              };
            };
            # ホストのNixのデータベースの写しを、VMのデータベースとして置きます。
            nix-db-seed = {
              description = "Seed Nix database from host";
              # ソケットは`basic.target`より前に起動するので、
              # 既定の依存関係を付けると順序が循環します。
              unitConfig.DefaultDependencies = false;
              after = [ "local-fs.target" ];
              before = [
                # nix-daemonが動き出す前に済ませる必要があるので、
                # ソケットより前に順序付けます。
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
                  # microvm.nixがVMのシステムのクロージャだけを登録したデータベースを先に作っています。
                  # ホストのデータベースにはそのクロージャも入っているので、丸ごと置き換えます。
                  "${lib.getExe' pkgs.coreutils "rm"} --force ${nixDbDir}/db.sqlite-wal ${nixDbDir}/db.sqlite-shm"
                  "${lib.getExe' pkgs.coreutils "install"} --mode=644 /run/host-nix-db/db.sqlite ${nixDbDir}/db.sqlite"
                ];
              };
            };
          };
          timers = {
            # 間隔は10分です。
            # 短くすると、続けて動くジョブの合間にキャッシュを捨ててしまい、
            # 次のジョブが同じファイルを読み直すことになります。
            # 長くしても、ホストがメモリを取り戻すのがその分遅れるだけです。
            reclaim-idle-memory = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "10min";
                OnUnitInactiveSec = "10min";
              };
            };
          };
        };
      };
    };
  vmUnits = lib.mapAttrsToList (name: _: "microvm@${name}.service") runnerVmDefs;
  # ホストのストアを書き換えるサービス。
  # 動いている間はVMを止めておく必要があります。
  storeWriterUnits = [
    "nix-gc"
    "nix-optimise"
  ];
  # 稼働中のsystemdと同じパッケージの`systemctl`。
  systemctl = lib.getExe' config.systemd.package "systemctl";
in
{
  imports = [ ../../../../pkgs/github-runner-store/module.nix ];

  microvm.vms = lib.mapAttrs mkRunnerVm runnerVmDefs;

  # VMを起動するたびにストアの状態を作り直すサービス。
  services.github-runner-store.vms = lib.mapAttrs (name: _: {
    overlayImage = overlayImageOf name;
  }) runnerVmDefs;

  local = {
    # ブートテストがVMの再起動とGCの前後の処理を確かめるために読みます。
    # Mackerelのチェックがランナの登録を確かめるためにも読みます。
    githubRunnerVms = lib.mapAttrs (name: def: {
      storeService = "${storeServiceOf name}.service";
      repository = repositoryOf def;
      runnerNames = runnerNamesOf def;
    }) runnerVmDefs;

    # CIランナの出口はインターネットだけ。
    #
    # ランナの中ではリポジトリのワークフローが持ち込んだコードが動く。
    # 必要な通信先はGitHubやcache.nixos.orgで、
    # niks3-public.ncaq.netへのキャッシュの登録も、
    # VMの中では公開DNSで引いてCloudflare Tunnel経由で届く。
    #
    # 自宅LAN、tailnet、他のコンテナ(forgejoの2222のようにホストでDNATされる経路も含む)に、
    # CIジョブを触らせる理由は無い。
    # TAPはコンテナのvethと違って名前を導けないので、VMの定義と同じ名前を明示する。
    machineEgress = lib.mapAttrs (_: def: {
      interface = def.tap;
      internet = true;
    }) runnerVmDefs;
  };

  systemd = {
    network.networks = lib.mkMerge (
      lib.mapAttrsToList (name: def: (tapNetworkOf name def.tap).host) runnerVmDefs
    );

    # 登録トークンは1時間で切れます。
    # ephemeralなランナはジョブが終わるたびに登録し直すので、
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
            GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY = repositoryOf def;
            GITHUB_RUNNER_REGISTRATION_TOKEN_API = "https://api.github.com";
            GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE =
              config.sops.secrets."runner-registration-pat".path;
          };
        }
      ) runnerVmDefs)

      # VMを起動するたびに、書き込み用の層を捨てて、
      # ホストのNixのデータベースの写しを取り直します。
      # サービスの本体は`pkgs/github-runner-store/module.nix`が定義していて、
      # ここではmicrovm.nixのユニットとの順序だけを足します。
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair (storeServiceOf name) {
          # イメージを置くディレクトリはmicrovm.nixのこのサービスが作ります。
          requires = [ "install-microvm-${name}.service" ];
          after = [ "install-microvm-${name}.service" ];
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
          ]
          # ストアを書き換える処理が起動を待っている間は、VMの起動も待たせます。
          # GCは終わる時に最適化の起動を頼んでからVMの起動を頼みます。
          # 順序が無いとVMはすぐ起動し始めて、直後に最適化の前処理に止められます。
          # 順序があるとVMの起動は最適化の起動を待ち、
          # 最適化の前処理が止める時に取り消されるので、VMは起動しかけません。
          # 最適化が動かない時は待つ相手が居ないので、そのまま起動します。
          ++ map (unit: "${unit}.service") storeWriterUnits;
        }
      ) runnerVmDefs)

      (lib.mapAttrs' (
        name: def:
        lib.nameValuePair "microvm-virtiofsd@${name}" {
          overrideStrategy = "asDropin";
          # 共有するディレクトリのマウントを待ちます。
          # `/mnt/noa`は`nofail`なので、
          # マウントに失敗してもブートは進みます。
          # 待たないと、
          # マウントされていない時にルートのSSDの上の空のディレクトリを共有して、
          # ジョブがそこへ書き込みます。
          # `microvm@`はこのユニットを`Requires`しているので、
          # マウントされていなければVMも起動しません。
          unitConfig.RequiresMountsFor = map (share: share.source) (def.extraShares or [ ]);
        }
      ) runnerVmDefs)

      # ホストのストアを書き換える処理の間はVMを止めて、終わってから新しい写しで起動し直します。
      # 処理が失敗しても起動し直すように、止めた後の処理として書きます。
      #
      # GCがパスを消すと、
      # VMのデータベースには有効なパスとして残るのに実体が無くなります。
      #
      # 最適化はパスを消しませんが、ファイルをハードリンクへ置き換えます。
      # VMが掴んでいた置き換え前のファイルは無くなり、
      # VMの中ではストアのファイルが開けなくなります。
      # ランナは次の登録で共有ライブラリを読み込めずに失敗して、
      # VMを起動し直すまで戻りませんでした。
      (lib.genAttrs storeWriterUnits (_: {
        preStart = "${systemctl} stop ${lib.concatStringsSep " " vmUnits}";
        postStop = "${systemctl} start --no-block ${lib.concatStringsSep " " vmUnits}";
      }))
    ];
  };
}
