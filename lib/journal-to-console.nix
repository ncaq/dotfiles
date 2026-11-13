/**
  コンテナとmicroVMの中のjournalをコンソールへ流すNixOSモジュール。
  ゲストの設定へ入れて使う。

  コンテナは`ephemeral`でmicroVMのルートはtmpfsなので、
  中のjournalは止めた時に消える。
  microVMにはsshdも無く、動いている間に中へ入って読むこともできない。
  障害が起きても原因を追えないまま再起動することになる。

  ゲストのコンソールの出力は、
  ホストのjournalへ`container@<名前>`や`microvm@<名前>`のユニットのログとして入る。
  ゲストのjournaldにコンソールへも書かせれば、
  中のサービスのログがホストのjournalに残り、
  ゲストを再起動した後も読める。
  読む時は`nixos/native-linux/machine-log.nix`の`machine-log`を使う。

  # 他の方法を採らない理由

  journalのディレクトリをホストと共有する方法や、
  ネットワーク越しにホストへ送る方法は、
  ゲストからホストへ書き込める経路を増やす。
  CIのランナーのmicroVMは持ち込まれたコードがrootで動く前提で隔離しているので、
  ホストがゲストの書いたjournalファイルを解析することも、
  ホストへの経路を開けることも避けたい。
  コンソールはゲストのrootが元から好きに書ける経路なので、
  ここへ流してもホストから見た攻撃面は増えない。

  代わりに構造化されたフィールドは失う。
  ホストのjournalではゲストのユニット名で絞り込めないので、
  `--grep`で絞る。

  # 量

  ゲストが書く量はゲストが決められるので、
  ホストの既定のjournalへそのまま入れると、
  大量に書くゲストがホスト自身の古いログを押し出せる。
  持ち込まれたコードが動くmicroVMの分は、
  ホスト側でVMごとのjournalのnamespaceへ分けて受けるので、
  押し出されるのはそのVM自身の古いログだけになる。
  分け方と、コンテナの分を分けていない理由は、
  `nixos/native-linux/machine-log.nix`に書いている。
*/
{
  # `/dev/console`は、microVMではシリアルコンソール、コンテナではnspawnが繋ぐptyを指す。
  services.journald.console = "/dev/console";
}
