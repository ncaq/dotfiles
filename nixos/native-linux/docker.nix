{
  lib,
  pkgs,
  username,
  ...
}:
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
      # APIソケットはsystemdのdocker.socketから受け取る。
      hosts = [ "fd://" ];
    };
    # RootlessKitのネットワークドライバをpasta(passt)にする。
    # passtはdockerパッケージに同梱されないので、デーモンのPATHへ足す。
    extraPackages = [ pkgs.passt ];
  };

  systemd.user = {
    services.docker = {
      # 既定のslirp4netnsはRootlessKitが`--ipv6`を渡しても名前空間の側にIPv6のアドレスと経路を作らず、
      # RAで自動設定させようにもdockerd-rootless.shが転送を有効にするのでRAを受け付けない。
      # 手で付けて試してもlibslirpの中継で外へ届かなかった。
      # pastaは`--config-net`でホストのアドレスと経路を名前空間へ写して自分でNATするので、
      # IPv4とIPv6の両方がホストと同じように外へ出る。
      # RootlessKitは`--ipv6`で有効にした時だけpastaへIPv4限定の指示を出さなくなる。
      # dockerd-rootless.shはslirp4netnsがPATHにあればそちらを選ぶので、ドライバを明示する。
      # 追加のフラグは`DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS`から読まれる。
      #
      # ポートドライバはpastaに合わせて`implicit`を明示する。
      # RootlessKit 2.3.6はpastaに`none`か`implicit`しか組み合わせさせない
      # (`builtin`を渡すと`network "pasta" requires port driver "none" or "implicit"`で起動しない)。
      # `implicit`ではpastaの`--tcp-ports=auto`と`--udp-ports=auto`が、
      # RootlessKitの名前空間の中でlistenされたポートをホスト側でも同じ番号でbindして転送する。
      # slirp4netns時代の`builtin`と違って`-p`で明示した公開だけに限られず、
      # `--network host`のコンテナのように名前空間を共有するプロセスが開いたポートもホストへ出る。
      # bulletで実測した挙動は以下の通り。
      #
      # - `-p 8080:80`はホストの127.0.0.1と::1の両方から届く
      # - `-p 127.0.0.1:8080:80`はホスト側ではワイルドカードでbindされるが、
      #   名前空間の中では127.0.0.1しかlistenしていないので、
      #   ループバック以外のアドレスへの接続は拒否される
      # - `--network host`のプロセスがlistenしたポートは`-p`無しでホストの全アドレスから届く
      #
      # ホストのfirewallは既定で拒否するので、
      # 転送されたポートがそのままLANやインターネットへ開くことは無い。
      # tailscale0のようにインターフェイス単位で許可している経路からは届き得るので、
      # `--network host`で待ち受けるコンテナはホストで直接動かすのと同じ露出があると考える。
      environment = {
        DOCKERD_ROOTLESS_ROOTLESSKIT_NET = "pasta";
        DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER = "implicit";
        DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS = "--ipv6";
      };
      # Dockerを使わない時間の方が長いのに、
      # デーモンは待機しているだけでもCPUを消費する。
      # ログイン時には起動せず、
      # APIソケットへ最初に接続された時にソケットアクティベーションで起動する。
      wantedBy = lib.mkForce [ ];
      requires = [ "docker.socket" ];
      after = [ "docker.socket" ];
    };
    # nixpkgsのrootlessモジュールはソケットユニットを用意しないので自前で定義する。
    # rootlesskitはLISTEN_FDSを子プロセスへ引き継ぐので、
    # 名前空間の中のdockerdが`fd://`でこのソケットを受け取れる。
    sockets.docker = {
      description = "Docker Socket for the API (Rootless)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "%t/docker.sock";
        SocketMode = "0600";
      };
    };
  };

  # rootlessコンテナ内のuid/gidマッピングに必要なsubuid/subgidを自動割り当てする。
  users.users.${username}.autoSubUidGidRange = true;
}
