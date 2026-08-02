{ lib, pkgs, ... }:
{
  services = {
    # スペースキーでのプレビュー実装。
    # NautilusはD-Busの`org.gnome.NautilusPreviewer`を呼ぶだけで中身を持っていない。
    # モジュールがdbusのサービスファイルも登録するのでGNOME外でも起動する。
    gnome.sushi.enable = true;
    # 仮想的なファイルシステムを扱う。
    gvfs.enable = true;
  };

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/nautilus/preferences" = {
          # デフォルトの`local-only`ではCIFSがリモート判定されてサムネイルが作られない。
          # スキーマの説明にある通り、
          # キー名に反して動画も含む全てのプレビュー可能な型に効く。
          show-image-thumbnails = "always";
          # サムネイル生成のファイルサイズ上限。
          # 単位はバイト。
          # Nautilusのデフォルトは50MB程度しかなく、
          # 動画ではほぼ全滅する。
          # メモリ上で安全に取り扱えるレベルの4GBに設定しておく。
          thumbnail-limit = lib.gvariant.mkUint64 (4 * 1024 * 1024 * 1024);
        };
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    gst-thumbnailers # GStreamerベースのサムネイラ
    nautilus # GNOMEのファイルマネージャ
  ];
}
