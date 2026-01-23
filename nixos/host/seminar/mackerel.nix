{
  config,
  ...
}:
let
  apiKeyConfigPath = "/run/mackerel-agent/apikey.conf";
in
{
  # Mackerel APIキー(純粋なキー文字列)をsopsで管理
  sops.secrets."mackerel-api-key" = {
    sopsFile = ../../../secrets/seminar/mackerel.yaml;
    key = "api_key";
    mode = "0400";
  };

  # sopsシークレットからTOML形式の設定ファイルを生成
  systemd.services.mackerel-agent-apikey-setup = {
    description = "Generate Mackerel API key config file";
    before = [ "mackerel-agent.service" ];
    requiredBy = [ "mackerel-agent.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "mackerel-agent";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      set -euo pipefail
      API_KEY=$(cat ${config.sops.secrets."mackerel-api-key".path})
      printf 'apikey = "%s"\n' "$API_KEY" > ${apiKeyConfigPath}
      chmod 0400 ${apiKeyConfigPath}
    '';
  };

  services.mackerel-agent = {
    enable = true;
    # 生成されたTOML形式の設定ファイルを使用
    apiKeyFile = apiKeyConfigPath;
    settings = {
      # エージェント自身のメモリ使用量も収集
      diagnostic = true;
      # ファイルシステムをデバイス名(dm-1等)ではなくマウントポイント名で表示
      filesystems.use_mountpoint = true;
    };
  };
}
