# Ollamaと同じコンテナで動かすWeb UI。
{
  pkgs,
  config,
  username,
  ...
}:
let
  openWebuiUid = 502;
  openWebuiGid = openWebuiUid;
  stateDir = config.local.ollama.openWebuiStateDir;
  ollama = config.containers.ollama.config.services.ollama;
  package = pkgs.open-webui;
in
{
  users = {
    users = {
      open-webui = {
        uid = openWebuiUid;
        group = "open-webui";
        isSystemUser = true;
      };
      ${username}.extraGroups = [ "open-webui" ];
    };
    groups.open-webui.gid = openWebuiGid;
  };

  containers.ollama = {
    # チャット履歴、設定、アップロードなどをコンテナの再作成後も保持する。
    extraFlags = [ "--bind=${stateDir}:${stateDir}:idmap" ];
    config =
      { lib, pkgs, ... }:
      {
        users = {
          users.open-webui = {
            uid = openWebuiUid;
            group = "open-webui";
            isSystemUser = true;
          };
          groups.open-webui.gid = openWebuiGid;
        };
        services.open-webui = {
          enable = true;
          inherit package stateDir;
          host = "0.0.0.0";
          port = 8080;
          # 認証を無効化するため、全接続元へfirewallを開かない。
          openFirewall = false;
          environment = {
            # 所有する端末だけのtailnetとACLを認証境界にするsingle-user mode。
            WEBUI_AUTH = "False";
            # 接続先をUIのDBへ保存させず、常に宣言したOllamaだけを使う。
            ENABLE_PERSISTENT_CONFIG = "False";
            OLLAMA_BASE_URL = "http://127.0.0.1:${toString ollama.port}";
            # ノートやカレンダーなどの組み込みツールを既定で渡さない。
            # Open WebUIはOllamaが申告するcapabilitiesを見ないため、
            # tools非対応のモデルにもfunction callingを要求してしまい、
            # `does not support tools`で会話そのものが失敗する。
            # モデル個別の設定が優先されるので、
            # 対応モデルだけUIから有効化できる。
            DEFAULT_MODEL_METADATA = builtins.toJSON { capabilities.builtin_tools = false; };
          };
        };
        # Tailscale Serveにつながるホスト側socket proxyからの接続だけを許可する。
        # ホストのFORWARDはACCEPTなので、
        # 他のコンテナからも自分のIPへ到達できてしまい、
        # 認証を無効化したUIには送信元の制限が必要になる。
        networking = {
          # `extraInputRules`はnftables backendでしか適用されず、
          # iptables backendでは何の警告もなく無視される。
          nftables.enable = true;
          firewall.extraInputRules = ''
            ip saddr ${config.containers.ollama.hostAddress} tcp dport 8080 accept
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
          };
        };
      };
  };

  # Open WebUIもOllamaと同じコンテナcgroup上限を共有する。
  # UI処理を含めてもホスト全体のメモリ保護を優先する。
  systemd.tmpfiles.rules = [ "d ${stateDir} 0750 open-webui open-webui - -" ];
}
