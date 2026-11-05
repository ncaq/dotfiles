/**
  NixOS Containerのvethのホスト側インターフェイス名を、
  nftablesの`iifname`や`networking.firewall.interfaces`で使える形で返す関数。

  nspawnはvethを`ve-<コンテナ名>`と名付けるが、
  Linuxのインターフェイス名はIFNAMSIZの制限で15文字までしか持てない。
  収まらない名前はsystemdの`shorten_ifname`が先頭11文字を残して、
  元の名前のハッシュから作った4文字を足した名前に縮める。
  実機では`ve-niks3-private`が`ve-niks3-preMOW`に、
  `ve-github-runner-dotfiles-x64`が`ve-github-retAS`になっている。

  縮めた後の4文字はNixから再現できないので、
  先頭11文字にワイルドカードを付けた形で返す。
  元の名前はaltnameとして残っていてsystemd-networkdの`matchConfig.Name`は拾えるが、
  nftablesの`iifname`は主名しか見ないため、
  firewallの側ではこの形でなければ何にも一致しない。

  同じ11文字を共有するコンテナは同じパターンに一致する。
  パターンでfirewallを開ける時はその全てに開くことになるので、
  使う側はそれで良いかを確かめること。

  # 引数

  - `lib`: 文字列操作に使う
  - `name`: コンテナ名
*/
{ lib, name }:
let
  full = "ve-${name}";
  # IFNAMSIZは終端のNULを含めて16なので、名前として使えるのは15文字まで。
  maxLength = 15;
  # 縮める時に残る先頭の長さ。15文字からハッシュの4文字を引いた11。
  keptLength = maxLength - 4;
in
if lib.stringLength full <= maxLength then full else "${lib.substring 0 keptLength full}*"
