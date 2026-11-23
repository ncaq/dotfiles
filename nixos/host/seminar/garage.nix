{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  # コンテナ内へbind mountされる環境ファイルのパス。
  # sops-nixの展開先はramfsでidmapped mountに対応していないため、
  # container@garageのExecStartPreがtmpfsである/runへ複製したものをbind mountする。
  envDir = "/run/garage";
  envFile = "${envDir}/garage.env";
  garageWithEnv = pkgs.writeShellApplication {
    name = "garage-with-env";
    runtimeInputs = [ ];
    text = ''
      set -a
      # shellcheck source=/dev/null
      source ${envFile}
      set +a
      exec garage "$@"
    '';
  };
  # コンテナ内のgarage CLIをホストから実行するためのラッパ。
  # GARAGE_RPC_SECRETなどを渡すために環境ファイルをexportする。
  garageWrapper = pkgs.writeShellApplication {
    name = "garage";
    runtimeInputs = with pkgs; [
      nixos-container
    ];
    text = ''
      exec nixos-container run garage -- ${lib.getExe garageWithEnv} "$@"
    '';
  };
in
{
  containers.garage = {
    local = {
      # どちらもbtrfsの上にあり、idmapped mountに対応している。
      persist = [
        "/var/lib/garage/meta"
        "/mnt/noa/garage/data"
      ];
    };
    # 環境ファイルはtmpfsの上にあり、idmapped mountに対応している。
    extraFlags = [ "--bind-ro=${envDir}:${envDir}:idmap" ];
    config = {
      networking.firewall.allowedTCPPorts = [
        3900 # S3 API
        3903 # Admin API (プライベートネットワーク経由でホストからのみアクセス)
      ];
      services.garage = {
        enable = true;
        package = pkgs.garage_2;
        environmentFile = envFile;
        settings = {
          metadata_dir = "/var/lib/garage/meta";
          data_dir = "/mnt/noa/garage/data";
          db_engine = "lmdb";
          metadata_auto_snapshot_interval = "6h";
          replication_factor = 1;
          rpc_bind_addr = "[::1]:3901";
          # 他のノードと`garage`のCLIがこのノードへ繋ぐ先。
          # 省くとCLIは`rpc_bind_addr`ではなく既定の`127.0.0.1:3901`へ繋ぎに行って失敗する。
          # 単一ノードなので待ち受けと同じloopbackを書く。
          rpc_public_addr = "[::1]:3901";
          s3_api = {
            s3_region = "garage";
            api_bind_addr = "[::]:3900";
            root_domain = ".garage.ncaq.net";
          };
          admin = {
            api_bind_addr = "[::]:3903";
          };
        };
      };
      # ホスト側bind mountの所有権と一致する明示的なUIDを使うためDynamicUserを無効化する。
      #
      # DynamicUserへ戻すには、データを全てStateDirectoryの下へ置いて、
      # 所有者をsystemdに任せることになる。
      # しかしコンテナのルートはephemeralで、StateDirectoryの親は起動のたびに作り直される。
      # systemdは親の所有者が合わなければ中身を再帰的にchownするので、
      # HDDの上の全てのデータブロックを起動のたびに辿ることになる。
      #
      # DynamicUser=trueが暗黙に有効化していたセキュリティ設定を再有効化し、
      # さらに追加のハードニングを上乗せする。
      # GarageはRustバイナリで、必要なのはS3/RPC/Admin APIのTCP通信と、
      # bind mountされたmetadata_dirとdata_dirへのファイルアクセスだけ。
      # これらは上流モジュールのStateDirectory/ReadWritePathsで書き込み可能になっている。
      systemd.services.garage.serviceConfig = hardening.network // {
        DynamicUser = lib.mkForce false;
        User = "garage";
        Group = "garage";
        # DynamicUser=trueが暗黙に有効化していたIPC隔離を再有効化する。
        RemoveIPC = true;
      };
      environment.systemPackages = [ pkgs.garage_2 ];
    };
  };

  # garageは外へ出ない。
  # `replication_factor = 1`の単一ノードで同期する相手が無く、
  # S3とAdmin APIのクライアントは全てこちらへ繋ぎに来る側なので、
  # 転送を1つも許さない。
  local.machineEgress.garage = { };

  systemd = {
    services."container@garage" = {
      requires = [ "sops-install-secrets.service" ];
      after = [ "sops-install-secrets.service" ];
      # sopsテンプレートの環境ファイルをtmpfsへ複製する。
      # 展開先の/run/secrets.dはramfsでidmapped mountできないため、
      # idmap対応のtmpfs(/run)に置き直してからコンテナへbind mountする。
      # コンテナ内ではPID 1(コンテナroot)がEnvironmentFileとして読むので、
      # idmapで同一視されるroot:rootの0400で置く。
      # 複製を独立したユニットで行うと以下の問題があるため、
      # コンテナ自身の起動処理に含めて寿命を一致させる。
      # - 独立ユニットの再起動でRuntimeDirectoryの/run/garageが作り直されると、
      #   bind mount済みのコンテナは削除済みの古いinodeを掴んだままになり、
      #   以後コンテナ内で環境ファイルが読めなくなる
      # - requires/afterだけでは独立ユニットのrestartがコンテナへ伝播しない
      serviceConfig = {
        # /run/garageはRuntimeDirectoryで管理して、
        # コンテナ停止時に平文シークレットごと自動削除させる。
        # systemdはRuntimeDirectoryをExecStartPreより前に作成するので複製に間に合う。
        # 上流モジュールがephemeral時に設定するnixos-containers/%iとはリストマージで共存する。
        # RuntimeDirectoryModeは指定しない。
        # ユニット内の全RuntimeDirectoryへ適用されるため、
        # 0700にするとコンテナルートFSのnixos-containers/%i(0755)のモードまで変わってしまう。
        # ディレクトリが0755でも環境ファイル自体が0400なので内容は漏れない。
        RuntimeDirectory = "garage";
        ExecStartPre = "${pkgs.coreutils}/bin/install -m 0400 ${
          config.sops.templates."garage-env".path
        } ${envFile}";
      };
    };
    # `local.persist`のディレクトリの親。
    tmpfiles.rules = [
      "d /var/lib/garage 0750 garage garage -"
      "d /mnt/noa/garage 0750 garage garage -"
    ];
  };

  environment.systemPackages = [ garageWrapper ];

  sops = {
    templates."garage-env" = {
      content = ''
        GARAGE_RPC_SECRET="${config.sops.placeholder."garage-rpc-secret"}"
        GARAGE_ADMIN_TOKEN="${config.sops.placeholder."garage-admin-token"}"
        GARAGE_METRICS_TOKEN="${config.sops.placeholder."garage-metrics-token"}"
      '';
      owner = "garage";
      group = "garage";
      mode = "0400";
      # シークレットのローテート時に/run/garageへの複製とコンテナ内のgarageを
      # 新しい内容で確実にやり直すため、コンテナごと再起動する。
      restartUnits = [ "container@garage.service" ];
    };
    # sops-nixで管理している。
    # 作成方法(初回のみ):
    # ```
    # rpc_secret=$(openssl rand -hex 32)
    # admin_token=$(openssl rand -base64 32)
    # metrics_token=$(openssl rand -base64 32)
    # ```
    # その後`sops secrets/seminar/garage.yaml`で以下を設定する:
    # ```
    # rpc_secret: <hex>
    # admin_token: <base64>
    # metrics_token: <base64>
    # ```
    secrets = {
      "garage-rpc-secret" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "rpc_secret";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
      "garage-admin-token" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "admin_token";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
      "garage-metrics-token" = {
        sopsFile = ../../../secrets/seminar/garage.yaml;
        key = "metrics_token";
        owner = "garage";
        group = "garage";
        mode = "0400";
      };
    };
  };

  # クラスタの初期セットアップ(手動、初回のみ):
  # ```
  # sudo garage status
  # sudo garage layout assign <node-id> -z seminar -c 8T
  # sudo garage layout apply --version 1
  # ```
}
