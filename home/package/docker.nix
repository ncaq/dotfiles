{ pkgs, ... }:
{
  home.packages = with pkgs; [
    docker-client
    docker-compose-language-service
    dockerfile-language-server-nodejs
    hadolint
  ];
}
