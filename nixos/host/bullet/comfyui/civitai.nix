# LoRA ManagerがCivitaiからモデルとメタデータを取得するための認証設定。
{
  config,
  ...
}:
{
  containers.comfyui = {
    # APIキーはsystemd credentialとしてコンテナへ渡す。
    # nspawnがホストroot権限で読んでコンテナのPID 1へ引き渡すため、
    # privateUsersのUIDマッピングやbind mountのパーミッションに依存せず、
    # ホスト側のファイルはroot専用の0400のままにできる。
    extraFlags = [ "--load-credential=civitai-env:${config.sops.templates."civitai-env".path}" ];
    # コンテナのPID 1が受け取ったシステムクレデンシャルを直接読む。
    # `/run/credentials/@system`はコンテナ内でもroot専用(0700)なので、
    # comfyuiユーザを含む他プロセスからは読めない。
    # LoadCredential + `%d`を使わないのは、
    # systemdがサービス個別のcredentialディレクトリを用意するより前に、
    # EnvironmentFileを読み込むため組み合わせられないから。
    config.systemd.services.comfyui.serviceConfig.EnvironmentFile =
      "/run/credentials/@system/civitai-env";
  };
  sops = {
    templates."civitai-env" = {
      content = ''
        CIVITAI_API_KEY=${config.sops.placeholder."civitai-api-key"}
      '';
      restartUnits = [ "container@comfyui.service" ];
    };
    # placeholder参照のための宣言。
    # `/run/secrets`に展開されるファイル自体はどこからも参照しない。
    secrets."civitai-api-key" = {
      sopsFile = ../../../../secrets/civitai.yaml;
      key = "api_key";
    };
  };
}
