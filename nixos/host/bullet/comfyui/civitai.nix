# LoRA ManagerがCivitaiからモデルとメタデータを取得するための認証設定。
{
  config,
  ...
}:
let
  environmentFile = "/run/comfyui/civitai-env";
in
{
  containers.comfyui = {
    # 通常ファイルへのidmap付きbind mountはEINVALになるため使わない。
    extraFlags = [ "--bind-ro=${config.sops.templates."civitai-env".path}:${environmentFile}" ];
    config.systemd.services.comfyui.serviceConfig.EnvironmentFile = environmentFile;
  };
  sops = {
    templates."civitai-env" = {
      content = ''
        CIVITAI_API_KEY=${config.sops.placeholder."civitai-api-key"}
      '';
      owner = "root";
      group = "root";
      # privateUsersのUIDマッピングを通さずbind mountするため、
      # コンテナ内のcomfyuiユーザが読み取れるようにする。
      # ホスト側では親ディレクトリがroot専用で、コンテナには読み取り専用で渡す。
      mode = "0444";
      restartUnits = [ "container@comfyui.service" ];
    };
    secrets."civitai-api-key" = {
      sopsFile = ../../../../secrets/civitai.yaml;
      key = "api_key";
      owner = "comfyui";
      group = "comfyui";
      mode = "0400";
      restartUnits = [ "container@comfyui.service" ];
    };
  };
}
