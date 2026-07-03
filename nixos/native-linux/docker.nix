{ username, ... }:
{
  # rootless Dockerを使う。
  # 常時rootで動くデーモンを避けるため。
  # podmanではなくDockerなのはBuildKitがそのまま動いてほしいから。
  # nixpkgsのdockerパッケージはbuildx(BuildKit)とcomposeプラグインを同梱している。
  virtualisation.docker.rootless = {
    enable = true;
    # DOCKER_HOSTをrootlessソケット(unix://$XDG_RUNTIME_DIR/docker.sock)に向ける。
    setSocketVariable = true;
  };

  # rootlessコンテナ内のuid/gidマッピングに必要なsubuid/subgidを自動割り当てする。
  users.users.${username}.autoSubUidGidRange = true;
}
