# テストVMのファイルシステムはvirtualisationモジュールが用意するbtrfsではないもので、
# autoScrubの対象が見つからずにassertionで評価が失敗するので無効化します。
# 月1回のタイマなのでブートテストの間に動くこともありません。
{ lib, ... }:
{
  services.btrfs.autoScrub.enable = lib.mkForce false;
}
