# gpg-vaultのagentのGNUPGHOMEへ置く設定ファイル。
#
# 入っているのは以下のファイルで、どの鍵を使うかには依らない。
#
# - `gpg-agent.conf`
# - ソケットを`socketDir`に作らせるリダイレクトのファイル。ソケットごとに1つ
#
# `module.nix`がこれらをgpg-vaultユーザのGNUPGHOMEへリンクして、gpg-agentを動かす。
# 鍵ごとに変わる`gpg.conf`と`sshcontrol`はここには無く、鍵をオプションで受け取る`module.nix`が作る。
#
# ソケットの場所と名前は`passthru`にも出している。
# `module.nix`とクライアント側の`home-module.nix`は、パスを自分では書かずにそこから引く。
#
# gpg-vaultが何のための仕組みかと、使い方は`README.md`に書いてある。
{
  homeManagerConfiguration,
  lib,
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
  # ssh-agentのエミュレーション用のソケットの名前。クライアント側が`SSH_AUTH_SOCK`に指す。
  sshSocketName = "S.gpg-agent.ssh";
  # agentの全てのコマンドを受け付けるソケットの名前。
  # 秘密鍵のエクスポートもできるので通常ユーザへは公開せず、gpg-vaultユーザとrootだけが繋ぐ。
  agentSocketName = "S.gpg-agent";
  # 制限付きのソケットの名前。
  # 署名と復号はできるが、秘密鍵のエクスポートやインポートや削除はagentが拒否する。
  # gpg-agentは設定しなくてもこのソケットを作る。
  extraSocketName = "S.gpg-agent.extra";
  # `socketDir`に作らせる全てのソケットの名前。
  socketNames = [
    agentSocketName
    extraSocketName
    sshSocketName
  ];
  # 通常ユーザのgpgとsshが探すソケットの名前から、その先に置くvaultのソケットの名前への対応。
  # gpgが普通のソケットとして探す名前の先を、制限付きのソケットにする。
  clientSocketLinks = {
    ${agentSocketName} = extraSocketName;
    ${sshSocketName} = sshSocketName;
  };
  # 通常ユーザへ公開するソケットの名前。
  # リンクの先になるソケットだけを公開するので、上の対応から導く。
  publicSocketNames = lib.unique (lib.attrValues clientSocketLinks);

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
      # パスフレーズの入力は、gpg-vaultユーザで動かすgpgが`--pinentry-mode loopback`で受け取ってagentへ渡します。
      # agentは別のユーザで動いていて、pinentryを通常ユーザの端末や画面に出せないためです。
      # 通常ユーザへ公開する制限付きのソケットからは、loopbackへの切り替えもagentが拒否します。
      allow-loopback-pinentry
      # そのためpinentryが入力を受け取ることはありませんが、
      # 設定として有効なパスは必要です。
      pinentry-program ${pinentry-curses}/bin/pinentry-curses
      # agentのユニットはデバイスを見せずに動かすので、スマートカードは使えません。
      # 鍵操作時にscdaemonがカード探索のためにspawnされるのを止めます。
      disable-scdaemon
    '')
  ]
  ++ map socketRedirect socketNames;
  passthru = {
    inherit
      agentSocketName
      clientSocketLinks
      extraSocketName
      publicSocketNames
      socketDir
      socketNames
      sshSocketName
      ;
    # ソケットの権限と、他のユーザから鍵が読めないことは、実際のユニットを動かさないと確かめられない。
    tests.nixos = import ./nixos-test.nix { inherit homeManagerConfiguration testers; };
  };
}
