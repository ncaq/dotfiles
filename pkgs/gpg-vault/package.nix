# GPG秘密鍵を通常ユーザから隔離するgpg-vaultの、GNUPGHOMEに置く静的な設定。
#
# 同じディレクトリの`module.nix`が、ここのファイルをgpg-vaultユーザのGNUPGHOMEへリンクして、
# そのGNUPGHOMEでgpg-agentを動かす。
# 何のために隔離するかは`module.nix`の冒頭に書いてある。
#
# 通常ユーザへ公開するソケットの場所は`socketDir`として`passthru`に出していて、
# `module.nix`とクライアント側の`home-module.nix`の両方がここから引く。
#
# ここに置くのは、どの鍵を使うかに依らないものだけ。
# 鍵ごとに変わる`gpg.conf`と`sshcontrol`は、鍵の情報をオプションで受け取る`module.nix`が作る。
{
  pinentry-curses,
  symlinkJoin,
  testers,
  writeTextDir,
}:
let
  # 通常ユーザへ公開するソケットを置くディレクトリ。
  # gpg-vaultはシステムユーザで/run/user/<uid>を持たないため、
  # 何もしないとソケットはGNUPGHOME直下に作られ、
  # mode 700のディレクトリ内なので通常ユーザから届かなくなります。
  socketDir = "/run/gpg-vault";

  # Assuanソケットリダイレクトで`socketDir`にソケットを作らせます。
  # gpg-agentはリダイレクトファイル自体は終了時に削除しない
  # (削除するのはリダイレクト先の実ソケットだけ)ことを検証済みなので、
  # storeへのsymlinkとして配置してもサービス再起動を跨いで機能します。
  socketRedirect =
    socketName:
    writeTextDir socketName ''
      %Assuan%
      socket=${socketDir}/${socketName}
    '';
in
symlinkJoin {
  name = "gpg-vault";
  paths = [
    (writeTextDir "gpg-agent.conf" ''
      enable-ssh-support
      # 鍵更新時に通常ユーザ側から`--pinentry-mode loopback`でパスフレーズ操作をするために必要です。
      # pinentryはユーザ境界を跨いで通常ユーザの端末を開けないためloopbackを使います。
      allow-loopback-pinentry
      # パスフレーズなし運用なのでpinentryが実際に呼ばれることはありませんが、
      # 設定として有効なパスは必要です。
      pinentry-program ${pinentry-curses}/bin/pinentry-curses
      # スマートカードは使わない運用なので、
      # 鍵操作時にscdaemonがカード探索のためにspawnされるのを止めます。
      disable-scdaemon
    '')
    (socketRedirect "S.gpg-agent")
    (socketRedirect "S.gpg-agent.ssh")
  ];
  passthru = {
    inherit socketDir;
    # ソケットの権限と、他のユーザから鍵が読めないことは、実際のユニットを動かさないと確かめられない。
    tests.nixos = import ./nixos-test.nix { inherit testers; };
  };
}
