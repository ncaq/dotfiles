{
  config,
  ...
}:
{
  services.mackerel-agent = {
    enable = true;
    runAsRoot = true;
    apiKeyFile = config.sops.templates."mackerel-api-key.conf".path;
    settings = {
      # エージェント自身のメモリ使用量も収集
      diagnostic = true;
      # ファイルシステムをデバイス名(dm-1等)ではなくマウントポイント名で表示
      filesystems.use_mountpoint = true;
    };
  };

  # Mackerel APIキー(純粋なキー文字列)をsopsで管理
  sops.secrets."mackerel-api-key" = {
    sopsFile = ../../../secrets/seminar/mackerel.yaml;
    key = "api_key";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # sops.templatesでTOML形式の設定ファイルを生成
  sops.templates."mackerel-api-key.conf" = {
    content = ''
      apikey = "${config.sops.placeholder."mackerel-api-key"}"
    '';
    mode = "0400";
  };
}
