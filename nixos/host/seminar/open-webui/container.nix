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
  stateDir = "/var/lib/open-webui";
  port = 8080;
  # unfreeの許可はホスト側のnixpkgsの設定にしかないため、
  # コンテナ内のpkgsではなくホスト側から取る。
  package = pkgs.open-webui;
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

  containers.open-webui = {
    # ホスト側のsocketへの初回アクセスで起動する。
    autoStart = false;
    ephemeral = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = addr.host;
    localAddress = addr.guest;
    # チャット履歴、設定、アップロードなどをコンテナの再作成後も保持する。
    # privateUsersによるUID変換後も固定UIDで読み書きできるようにidmapを付ける。
    extraFlags = [ "--bind=${stateDir}:${stateDir}:idmap" ];
    config =
      {
        lib,
        pkgs,
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
          };
          groups.open-webui.gid = user.gid;
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
          environment = options.services.open-webui.environment.default // {
            # 所有する端末だけのtailnetとACLを認証境界にするsingle-user mode。
            WEBUI_AUTH = "False";
            # 接続先をUIのDBへ保存させず、常に宣言したOllamaだけを使う。
            ENABLE_PERSISTENT_CONFIG = "False";
            # ホスト側のCaddyがbullet優先でOllamaへ振り分ける。
            OLLAMA_BASE_URL = "http://${addr.host}:${toString config.local.openWebui.ollamaPort}";
            # ノートやカレンダーなどの組み込みツールを既定で渡さない。
            # Open WebUIはOllamaが申告するcapabilitiesを見ないため、
            # tools非対応のモデルにもfunction callingを要求してしまい、
            # `does not support tools`で会話そのものが失敗する。
            # モデル個別の設定が優先されるので、
            # 対応モデルだけUIから有効化できる。
            DEFAULT_MODEL_METADATA = builtins.toJSON { capabilities.builtin_tools = false; };
          };
        };
        # 埋め込みモデルの取得などで名前解決が必要になる。
        services.resolved.enable = true;
        networking = {
          useHostResolvConf = lib.mkForce false;
          # Tailscale Serveにつながるホスト側socket proxyからの接続だけを許可する。
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

  systemd = {
    services."container@open-webui".serviceConfig = {
      # RAGの文書取り込みでは埋め込みモデルがプロセス内で動き、
      # torchがコア数分のスレッドを立てて数GiB規模のRSSが数分続く。
      # 常時起動のホストで他のワークロードを巻き添えにしないよう上限を設ける。
      # OSや他の処理のために2スレッド分を残す既存のCPU予算を使う。
      CPUQuota = "${toString (config.local.cpuBudgetThreads * 100)}%";
      MemoryHigh = "8G"; # ソフトリミット。これを超えるとメモリを積極的に解放する。
      MemoryMax = "16G"; # ハードリミット。大きな文書の取り込みでも足りるだろうという推定値。
    };
    # NixOSコンテナモジュールが生成するpostStartは`ip addr add`と`ip route add`を使うため、
    # systemd-networkdが先に設定済みだとEEXISTで失敗する。
    # 実際の設定はsystemd-networkdに任せるので、冪等にして失敗を無視する。
    services."container@open-webui".postStart = lib.mkForce ''
      ifaceHost=ve-$INSTANCE
      ip link set dev "$ifaceHost" up
      ip addr add ${addr.host} dev "$ifaceHost" 2>/dev/null || true
      ip route add ${addr.guest} dev "$ifaceHost" 2>/dev/null || true
    '';
    # vethのアドレスとルートをsystemd-networkdで設定する。
    # 何も宣言しないとsystemdに同梱の`80-container-ve.network`が適用されて、
    # link localアドレスと動的な/28がvethに乗る。
    # するとコンテナ宛の送信元アドレスがそちらから選ばれてしまい、
    # コンテナ側で`hostAddress`からの接続だけを許可しているルールにマッチしない。
    network.networks."20-open-webui-veth" = {
      matchConfig.Name = "ve-open-webui";
      addresses = [ { Address = "${addr.host}/32"; } ];
      routes = [ { Destination = "${addr.guest}/32"; } ];
    };
    # コンテナへidmap bindする永続データ領域をホスト側に用意する。
    tmpfiles.rules = [ "d ${stateDir} 0750 open-webui open-webui - -" ];
  };
}
