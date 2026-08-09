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

  tailscale CLIはtailscaledのLocalAPIにUNIXソケット経由で接続するだけで、
  実際のプロキシ転送はtailscaled側が行うため、
  UNIXソケットのみ許可のハードニングまで絞れる。
  このサンドボックス下でServiceの登録、
  drainによる停止、
  再起動での再advertise、
  公開URLへのHTTPSアクセスが通ることをbullet上で確認済み。
*/
{
  pkgs,
  tailscale,
  service,
  label,
  port,
  socket,
}:
let
  hardening = import ./systemd-hardening.nix;
  lockFile = "/run/lock/tailscale-serve.lock";
  serialize = command: "${pkgs.lib.getExe' pkgs.util-linux "flock"} ${lockFile} ${command}";
in
{
  description = "Tailscale Serve for ${label}";
  requires = [ "tailscaled.service" ];
  wants = [
    socket
    "tailscale-online.service"
  ];
  after = [
    socket
    "tailscale-online.service"
    "tailscaled.service"
  ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = hardening.unixSocket // {
    Type = "oneshot";
    RemainAfterExit = true;
    # Tailscale Serviceは設定をtailscaledへ永続化してコマンド自体は終了する。
    ExecStart = serialize "${tailscale}/bin/tailscale serve --service=${service} --https=443 http://127.0.0.1:${toString port}";
    # endpoint設定は残して、次回起動時にそのまま再advertiseできるようにする。
    ExecStop = serialize "${tailscale}/bin/tailscale serve drain ${service}";
    # ロックファイルを置くためだけに書き込みを許可する。
    ReadWritePaths = [ "/run/lock" ];
  };
}
