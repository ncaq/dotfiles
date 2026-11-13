# NixOSテストフレームワークがrootに`hashedPasswordFile`を自動設定するため、
# user.nixで設定している`hashedPassword`と重複定義の警告が出ます。
# テスト環境ではrootパスワードは不要なので`hashedPassword`を無効化して警告を除去します。
{ lib, ... }:
{
  users.users.root.hashedPassword = lib.mkForce null;
}
