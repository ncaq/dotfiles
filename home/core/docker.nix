{ pkgs, ... }:
{
  # Dockerクライアント設定(~/.docker/config.jsonとDOCKER_CONFIG)を
  # home-managerで宣言的に管理する。
  # このモジュールはパッケージを入れないのでdocker-clientは別途入れる。
  # config.jsonがNixストアへの読み取り専用リンクになるため、
  # docker loginが必要になったらsettings.credsStoreでcredential helperを宣言する。
  programs.docker-cli.enable = true;

  home.packages = with pkgs; [
    act
    docker-client # clientOnlyなdockerパッケージ。buildx(BuildKit)とcomposeプラグイン同梱。
    docker-compose-language-service
    dockerfile-language-server
    hadolint
  ];
}
