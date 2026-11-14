/**
  プレフィックス長の無いIPv6アドレスを読んで、
  省略しない小文字の形に揃えた文字列を返す関数。
  読めなければ`null`を返す。

  型: String -> String | null

  読み取りはnixpkgsの`lib.network.ipv6.fromString`に任せる。
  あちらは読めない入力で`throw`し、
  返り値の`address`は遅延評価されるので、
  `address`の文字列を強制するところで1度だけ捕まえる。
  呼び出し側がそれぞれ`tryEval`を書くと、
  強制する範囲がずれて例外を捕まえ損ねることがある。

  `fromString`はプレフィックス長を省くと128とみなすので、
  付いていたかは入力の字面で見て、付いていれば読めないものとして扱う。
  アドレス1つを指定する所で範囲を渡せてしまわないようにするため。

  ```nix
  parseIpv6 "FDF2:a855:5a3f:0100::011"
  => "fdf2:a855:5a3f:100:0:0:0:11"
  parseIpv6 "192.168.100.11"
  => null
  ```

  検査は`test/eval/parse-ipv6.nix`で固定している。

  # 引数

  - `lib`: IPv6アドレスの読み取りと文字列操作に使う
*/
{ lib }:
address:
let
  result = builtins.tryEval (lib.network.ipv6.fromString address).address;
in
if !(lib.hasInfix "/" address) && result.success then result.value else null
