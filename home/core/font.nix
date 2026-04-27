{ pkgs, lib, ... }:
let
  # フォントエイリアスをマッピングで管理。
  fontAliases = {
    # webサイトが指定しがちな典型的なGNU/Linux環境を想定したフォントを総称フォントに戻して自分の好きなフォントで読みます。
    "DejaVu Sans" = "sans-serif";
    "Liberation Mono" = "monospace";
    "Liberation Sans" = "sans-serif";
    # MS系レガシーフォントを総称フォントにマッピングします。
    # PostScript名をだいたいカバーしたものを指定します。
    # ゴシック系のプロポーショナル。
    "MS PGothic" = "sans-serif";
    "MS UIGothic" = "sans-serif";
    "MS-PGothic" = "sans-serif";
    # ゴシック系の等幅。
    "MS Gothic" = "monospace";
    "MS-Gothic" = "monospace";
    # 明朝系。
    "MS Mincho" = "serif";
    "MS PMincho" = "serif";
    "MS-Mincho" = "serif";
    "MS-PMincho" = "serif";
  };
  # フォントの写像をfontconfigの形式に変換する関数。
  generateMatchEntry = originalFamily: targetFamily: ''
    <match target="pattern">
      <test name="family"><string>${originalFamily}</string></test>
      <edit name="family" binding="same" mode="assign"><string>${targetFamily}</string></edit>
    </match>
  '';
  # フォントエイリアスからfontconfigの実際の設定ファイルを生成する関数。
  generateOverrideConf =
    aliases:
    let
      header = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
      '';
      body = lib.concatStringsSep "\n" (lib.mapAttrsToList generateMatchEntry aliases);
      footer = "</fontconfig>";
    in
    header + "\n" + body + "\n" + footer;
in
{
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      sansSerif = [
        "Fira Sans" # Mozillaが開発したサンセリフ書体。
        "BIZ UDGothic" # 日本語のユニバーサルデザインのゴシック体。
        "emoji" # 絵文字向けフォールバック。
      ];
      serif = [
        "Zilla Slab" # Mozillaが開発したセリフ書体。
        "Noto Serif CJK JP" # GoogleとAdobeが開発した日本語のセリフ体。源ノ明朝とも呼ばれます。
        "emoji" # 絵文字向けフォールバック。
      ];
      monospace = [
        # Fira Mono と源真ゴシックを合成したプログラミングフォント。
        # Console版はFira Monoを優先して多くの記号が半角になります。
        # Nerd Fonts版はアイコンなどが追加されています。
        "FirgeNerd Console"
        "emoji" # 絵文字向けフォールバック。
      ];
      emoji = [
        "Noto Color Emoji" # Googleが開発したカラーフォントの絵文字。
      ];
    };
  };

  # 後ろの方に設定ファイルを生成することで特定のフォントを総称フォントにマッピングします。
  xdg.configFile."fontconfig/conf.d/90-override.conf".text = generateOverrideConf fontAliases;

  # 表示されてあまり困らないフォントを雑に追加します。
  home.packages = with pkgs; [
    biz-ud-gothic
    fira
    firge-font
    firge-nerd-font
    hackgen-nf-font
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    zilla-slab
  ];
}
