# Ollamaのチャット用Web UIを動かすNixOS Containerの定義。
#
# 常時起動のseminarだけで動かして、チャット履歴を1箇所へ集約する。
# UI自体は負荷の軽い処理なのでseminarのCPUで足りる。
# 推論は`ollama-backend.nix`がbulletのOllamaへ優先的に振り分ける。
{
  lib,
  pkgs,
  config,
  username,
  ...
}:
let
  addr = config.machineAddresses.open-webui;
  user = config.serviceUser.open-webui;
  postgresGid = config.serviceUser.postgres.gid;
  stateDir = "/var/lib/open-webui";
  port = 8080;
  # コンテナのモジュールでは`config`がコンテナ自身のものになるため、
  # ホスト側のオプションはここで束縛しておく。
  ollamaPort = config.local.openWebui.ollamaPort;
  # `environment.nix`が集めた設定。これもホスト側の`config`から取る。
  extraEnvironment = config.local.openWebui.environment;
  # unfreeの許可はホスト側のnixpkgsの設定にしかないため、
  # コンテナ内のpkgsではなくホスト側から取る。
  #
  # 上流はPostgreSQL接続の同期エンジンにpsycopg2を使うが、
  # nixpkgsはpsycopg2-binaryとpgvectorを`optional-dependencies.postgres`へ
  # 分離しているため、依存へ加えて構築する。
  package = pkgs.open-webui.overridePythonAttrs (old: {
    dependencies = old.dependencies ++ pkgs.open-webui.optional-dependencies.postgres;
  });
in
{
  # コンテナ内と同じIDでホスト側にもユーザとグループを作る。
  # bind mountした永続データ領域の所有者をホストからも名前で扱えるようにするため。
  users = {
    users = {
      open-webui = {
        inherit (user) uid;
        group = "open-webui";
        isSystemUser = true;
      };
      ${username}.extraGroups = [ "open-webui" ];
    };
    groups.open-webui.gid = user.gid;
  };

  # PostgreSQLコンテナ側にデータベースとpeer認証のユーザを用意させる。
  postgresClient = [ "open-webui" ];

  # ベクトル検索に使うpgvector拡張をデータベースへ有効化させる。
  postgresExtension.open-webui = [ "vector" ];

  containers.open-webui = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    # PostgreSQLのpeer認証がホストと同一のUIDでの接続を要求するため、
    # pickにはできずidentity(UID分離なし、capability分離のみ)にする。
    privateUsers = "identity";
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      # DBとベクトルはPostgreSQLへ移したため、
      # ここに残るのはアップロードされたファイルや埋め込みモデルのキャッシュなどで、
      # それらをコンテナの再作成後も保持する。
      "${stateDir}" = {
        hostPath = stateDir;
        isReadOnly = false;
      };
      # PostgreSQLコンテナとのUnixソケット共有。
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = true;
      };
    };
    config =
      {
        lib,
        pkgs,
        config,
        options,
        ...
      }:
      {
        system.stateVersion = "26.05";
        time.timeZone = "Asia/Tokyo";
        users = {
          users.open-webui = {
            inherit (user) uid;
            group = "open-webui";
            isSystemUser = true;
            # `/run/postgresql`が0750 postgres:postgresのため、
            # ソケットへ到達するにはpostgresグループへの所属が必要。
            extraGroups = [ "postgres" ];
          };
          groups = {
            open-webui.gid = user.gid;
            postgres.gid = postgresGid;
          };
        };
        services.open-webui = {
          enable = true;
          inherit package stateDir port;
          host = "0.0.0.0";
          # 認証を無効化するため、全接続元へfirewallを開かない。
          openFirewall = false;
          # `environment`を定義すると既定値は丸ごと置き換わり、
          # 匿名の利用統計を外部送信しない設定が失われる。
          # 値を書き写すと二重管理になるので、オプションの既定値からマージする。
          #
          # ここに直接書くのはコンテナの構造そのものを決める変数だけにして、
          # 管理画面や設定画面から触る類の設定は`environment.nix`へ集める。
          # あちらを先に重ねるのは、
          # 認証や永続化の方針が設定の一項目として上書きされるのを防ぐためである。
          environment =
            options.services.open-webui.environment.default
            // extraEnvironment
            // {
              # 所有する端末だけのtailnetとACLを認証境界にするsingle-user mode。
              WEBUI_AUTH = "False";
              # 接続先をUIのDBへ保存させず、常に宣言したOllamaだけを使う。
              ENABLE_PERSISTENT_CONFIG = "False";
              # チャット履歴などのDBを既定のSQLiteではなくPostgreSQLに置く。
              # `postgresql.nix`のコンテナへUnixソケット経由のpeer認証で接続する。
              # sameuserルールに合わせてユーザ名とデータベース名を一致させる。
              DATABASE_URL = "postgresql://open-webui@/open-webui?host=/run/postgresql";
              # RAGのベクトルも既定のchroma(コンテナ内のSQLite)ではなく、
              # 本体と同じデータベースのpgvector拡張に置く。
              # `PGVECTOR_DB_URL`は未指定なら`DATABASE_URL`を使う。
              #
              # 公式が継続メンテナンスするエンジンはchromaとpgvectorだけで、
              # chromaはfork-safeではなく並行アップロードでワーカーが落ちる問題も知られている。
              # ref https://github.com/ncaq/blue-prompt/issues/183
              VECTOR_DB = "pgvector";
              # pgvector拡張はtrustedではなくアプリのユーザでは作成できないため、
              # `postgresql.nix`のsetupサービスがsuperuserで作成する。
              PGVECTOR_CREATE_EXTENSION = "False";
              # 既定のivfflatは空のテーブルへ索引を作るとリストの割り当てが偏り、
              # 後から方式を変えるには手動での索引の削除も要求される。
              # 逐次の追記に強くパラメータ調整も不要なHNSWを最初から選ぶ。
              PGVECTOR_INDEX_METHOD = "hnsw";
              # プールサイズが未設定だとNullPoolになり、
              # セッション取得のたびにPostgreSQLバックエンドのfork+認証が走る。
              # SQLiteではファイルアクセスで実質ゼロだった接続コストが、
              # 短いクエリを多数投げる経路で支配的になるため、
              # 正の整数を与えてpool_pre_ping付きのQueuePoolへ切り替える。
              #
              # 数値は必要量と上限の挟み撃ちで決めた推定値である。
              # UIのページロード時に並列で飛ぶAPI(10本前後)をプールで吸収し、
              # Knowledge同期の書き込みと重なるバーストをオーバーフローで逃がす。
              # 上限側はPostgreSQLのmax_connections(既定100)を全クライアントで共有するが、
              # ここの最悪合計(10+20+5と僅かな同期エンジン分)では圧迫しない。
              DATABASE_POOL_SIZE = "10";
              DATABASE_POOL_MAX_OVERFLOW = "20";
              # RAG検索が使うpgvector側のエンジンは別プール。
              PGVECTOR_POOL_SIZE = "5";
              # ホスト側のCaddyがbullet優先でOllamaへ振り分ける。
              OLLAMA_BASE_URL = "http://${addr.host}:${toString ollamaPort}";
            };
        };
        # 埋め込みモデルの取得などで名前解決が必要になる。
        services.resolved.enable = true;
        networking = {
          useHostResolvConf = lib.mkForce false;
          # Tailscale Serveの転送先として中継する、ホスト側のCaddyからの接続だけを許可する。
          # ホストのFORWARDはACCEPTなので、
          # 他のコンテナからも自分のIPへ到達できてしまい、
          # 認証を無効化したUIには送信元の制限が必要になる。
          #
          # `extraInputRules`はnftables backendでしか適用されず、
          # iptables backendでは何の警告もなく無視される。
          nftables.enable = true;
          firewall.extraInputRules = ''
            ip saddr ${addr.host} tcp dport ${toString port} accept
          '';
        };
        # 送信元の制限が黙って無効化されることは評価時に防げる。
        assertions = [
          {
            assertion = config.networking.nftables.enable;
            message = "open-webui container requires the nftables backend for firewall.extraInputRules to take effect";
          }
        ];
        # bind mountしたStateDirectoryを固定ユーザで扱う。
        systemd.services.open-webui = {
          # 音声ファイルの変換などに使うffmpegを実行パスへ追加する。
          path = [ pkgs.ffmpeg-headless ];
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "open-webui";
            Group = "open-webui";
            # StateDirectoryのモードは起動ごとにsystemdが強制するため、
            # tmpfilesで宣言するだけでは既定の0755へ戻されてしまう。
            StateDirectoryMode = "0750";
          };
        };
      };
  };

  systemd = lib.mkMerge [
    (import ../../../../lib/container-veth.nix {
      inherit lib;
      name = "open-webui";
      inherit addr;
    })
    {
      services."container@open-webui" = {
        # DBが接続を受け付けてから起動しないと、
        # 起動時のマイグレーションが失敗する。
        requires = [ "postgresql-ready.service" ];
        after = [ "postgresql-ready.service" ];
        serviceConfig = {
          # RAGの文書取り込みでは埋め込みモデルがプロセス内で動き、
          # torchがコア数分のスレッドを立てて数GiB規模のRSSが数分続く。
          # 常時起動のホストで他のワークロードを巻き添えにしないよう上限を設ける。
          # OSや他の処理のために2スレッド分を残す既存のCPU予算を使う。
          CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
          MemoryHigh = "8G"; # ソフトリミット。これを超えるとメモリを積極的に解放する。
          MemoryMax = "16G"; # ハードリミット。大きな文書の取り込みでも足りるだろうという推定値。
        };
      };
      # コンテナへbind mountする永続データ領域をホスト側に用意する。
      tmpfiles.rules = [ "d ${stateDir} 0750 open-webui open-webui - -" ];
    }
  ];
}
