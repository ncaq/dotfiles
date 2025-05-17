{ pkgs, ... }:
{
  home.packages = with pkgs; [
    act
    docker-client
    docker-compose-language-service
    dockerfile-language-server-nodejs
    hadolint
  ];
}
