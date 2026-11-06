{ pkgs, username, ... }:
{
  # rootless Dockerを使う。
  # 常時rootで動くデーモンを避けるため。
  # podmanではなくDockerなのはBuildKitがそのまま動いてほしいから。
  # nixpkgsのdockerパッケージはbuildx(BuildKit)とcomposeプラグインを同梱している。
  virtualisation.docker.rootless = {
    enable = true;
    # DOCKER_HOSTをrootlessソケット(unix://$XDG_RUNTIME_DIR/docker.sock)に向ける。
    setSocketVariable = true;
    # 既定のbridge(docker0)にIPv6を付ける。
    # rootlessではdockerdがRootlessKitの作るネットワーク名前空間の中で動き、
    # 名前空間の外へはpastaが中継する。
    # dockerd側でIPv6を有効にしないとコンテナにはIPv6アドレスも経路も付かず、
    # IPv6でしか繋がらない宛先に届かない。
    # プレフィックスはRFC 4193のULAで、
    # NixOSコンテナの`lib/machine-address6.nix`やtailnetと重ならない値を乱数で決めた。
    # コンテナから外へはdockerdが名前空間の側のアドレスへ付け替えて出すので、
    # この値はホストの外からは見えない。
    daemon.settings = {
      ipv6 = true;
      "fixed-cidr-v6" = "fd3e:91b7:2c04::/64";
    };
    # RootlessKitのネットワークドライバをpasta(passt)にする。
    # passtはdockerパッケージに同梱されないので、デーモンのPATHへ足す。
    extraPackages = [ pkgs.passt ];
  };

  # 既定のslirp4netnsはRootlessKitが`--ipv6`を渡しても名前空間の側にIPv6のアドレスと経路を作らず、
  # RAで自動設定させようにもdockerd-rootless.shが転送を有効にするのでRAを受け付けない。
  # 手で付けて試してもlibslirpの中継で外へ届かなかった。
  # pastaは`--config-net`でホストのアドレスと経路を名前空間へ写して自分でNATするので、
  # IPv4とIPv6の両方がホストと同じように外へ出る。
  # RootlessKitは`--ipv6`で有効にした時だけpastaへIPv4限定の指示を出さなくなる。
  # dockerd-rootless.shはslirp4netnsがPATHにあればそちらを選ぶので、ドライバを明示する。
  # 追加のフラグは`DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS`から読まれる。
  systemd.user.services.docker.environment = {
    DOCKERD_ROOTLESS_ROOTLESSKIT_NET = "pasta";
    DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS = "--ipv6";
  };

  # rootlessコンテナ内のuid/gidマッピングに必要なsubuid/subgidを自動割り当てする。
  users.users.${username}.autoSubUidGidRange = true;
}
