/**
  ホスト上のポートをTailscale Serviceとしてtailnet内へ公開するサービスを生成する関数。

  `tailscale serve --service=`はtailscaledのprefsにある`AdvertiseServices`を、
  読み込んでから書き戻す形で更新する。
  ホストが複数のServiceを公開していると、
  systemdが順序を持たないユニットを同時に起動した際に更新が互いを上書きして、
  advertiseされないServiceが出る。
  実際にbulletで複数のServiceを同時に再起動すると、
  毎回どれかが落ちる状態を再現している。
  落ちたServiceはDNSこそ引けるので、
  接続がタイムアウトするまで気付けない。

  ホスト上の全てのserveユニットで同じロックを取り、
  Serviceの登録と解除を直列に実行する。

  転送先はsocket activationのproxyを想定している。
  tailnet経由の初回アクセスでもオンデマンド起動が機能する。

  HTTPSに加えて80番のHTTPリスナーも張り、
  `nixos/tailscale-serve/http-redirect.nix`のCaddyへ転送してHTTPSへリダイレクトする。
  Serve自体にリダイレクトを返すターゲットが無いため転送先が要る。
  80番が閉じたままだと`http://`で飛んできた時にTCP接続ごと拒否される。
  80番はTailscale Serviceの定義側でも開ける必要があり、
  infra.ncaq.netの`tailscale/service.tf`と`tailscale/access-policy.tf`に`tcp:80`が要る。

  tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけで、
  実際のプロキシ転送はtailscaled側が行うため、
  UNIXソケットのみ許可のハードニングまで絞れる。
  このサンドボックス下でServiceの登録、
  drainによる停止、
  再起動での再advertise、
  公開URLへのHTTPSアクセスが通ることをbullet上で確認済み。

  # 引数

  - `pkgs`: flockの実行に使うパッケージの供給元
  - `hardening`: `lib/systemd-hardening.nix`の設定集。
    NixOSモジュールへは`flake.nix`の`specialArgs`経由で配布されるものをそのまま渡す
  - `tailscale`: 使うtailscaleのパッケージ
  - `service`: `svc:`から始まるTailscale Service名
  - `label`: ユニットのdescriptionに出る人間向けの表示名
  - `port`: 転送先のホスト側ポート番号
  - `socket`: 転送先のsocketユニット名
  - `redirectPort`: HTTPSリダイレクタのポート番号。
    `config.local.tailscaleServe.redirectPort`をそのまま渡す
*/
{
  pkgs,
  hardening,
  tailscale,
  service,
  label,
  port,
  socket,
  redirectPort,
}:
let
  lockFile = "/run/lock/tailscale-serve.lock";
  serialize = command: "${pkgs.lib.getExe' pkgs.util-linux "flock"} ${lockFile} ${command}";
in
{
  description = "Tailscale Serve for ${label}";
  requires = [ "tailscaled.service" ];
  wants = [
    socket
    "caddy.service"
    "tailscale-online.service"
  ];
  after = [
    socket
    "caddy.service"
    "tailscale-online.service"
    "tailscaled.service"
  ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = hardening.unixSocket // {
    Type = "oneshot";
    RemainAfterExit = true;
    # Tailscale Serviceは設定をtailscaledへ永続化してコマンド自体は終了する。
    ExecStart = [
      (serialize "${tailscale}/bin/tailscale serve --service=${service} --https=443 http://127.0.0.1:${toString port}")
      (serialize "${tailscale}/bin/tailscale serve --service=${service} --http=80 http://127.0.0.1:${toString redirectPort}")
    ];
    # endpoint設定は残して、次回起動時にそのまま再advertiseできるようにする。
    ExecStop = serialize "${tailscale}/bin/tailscale serve drain ${service}";
    # ロックファイルを置くためだけに書き込みを許可する。
    ReadWritePaths = [ "/run/lock" ];
  };
}
