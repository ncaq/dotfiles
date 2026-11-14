# home-managerによるユーザ環境の有効化を止めます。
# テストVMには秘密情報が無いので、有効化は最後のsops-nixの復号で必ず失敗します。
# 失敗するまでにホームのファイルのリンクやEmacsのデーモンの起動で3分半ほどかかり、
# その間ずっと`multi-user.target`への到達を止めます。
# 結果が決まっているものを待つだけなので、ユニットごと無効化します。
# home-managerの構成がビルドできることは、
# CIが`ciJobs`の中で実機の構成をビルドして確かめています。
{ lib, username, ... }:
{
  systemd.services."home-manager-${username}".enable = lib.mkForce false;
}
