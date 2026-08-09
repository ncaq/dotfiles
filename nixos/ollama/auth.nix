# Ollamaアカウントへ登録した署名鍵をコンテナへ渡す。
# 公開鍵のアカウント登録だけはOllamaに非対話APIがないため初回に手動で行う。
# https://ollama.com/settings/keys
# もしくは
# ```
# ollama signin
# ```
{ config, ... }:
let
  credentialName = "ollama-id-ed25519";
  systemCredential = "/run/credentials/@system/${credentialName}";
  keyDir = "${config.local.ollama.dataDir}/.ollama";
  keyPath = "${keyDir}/id_ed25519";
in
{
  # nspawnがホストrootとしてsops secretを読み、コンテナPID 1のcredentialへ渡す。
  # privateUsersのUIDマッピングに依存せず、ホスト側ではroot専用のまま保持できる。
  containers.ollama = {
    extraFlags = [
      "--load-credential=${credentialName}:${config.sops.secrets.${credentialName}.path}"
    ];
    config.systemd = {
      services.ollama.serviceConfig = {
        # コンテナPID 1のsystem credentialをOllamaサービス専用に複製する。
        LoadCredential = "${credentialName}:${systemCredential}";
        # 秘密鍵を永続領域へコピーせず、Ollamaが要求する固定パスで見せる。
        BindReadOnlyPaths = "%d/${credentialName}:${keyPath}";
      };
      tmpfiles.rules = [
        "d ${keyDir} 0700 ollama ollama - -"
        # service credentialをread-only bindするためのmount point。
        "f ${keyPath} 0600 ollama ollama - -"
      ];
    };
  };

  sops.secrets.${credentialName} = {
    sopsFile = ../../secrets/ollama.yaml;
    key = "private_key";
    restartUnits = [ "container@ollama.service" ];
  };

  systemd.services."container@ollama" = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
  };
}
