{ pkgs, lib, ... }:
let
  # フォントエイリアスをマッピングで管理。
  fontAliases = {
    # webサイトが指定しがちな典型的なGNU/Linux環境を想定したフォントを総称フォントに戻して自分の好きなフォントで読みます。
    # sans-serif系。
    "DejaVu Sans" = "sans-serif";
    "Liberation Sans" = "sans-serif";
    # monospace系。
    "DejaVu Sans Mono" = "monospace";
    "Liberation Mono" = "monospace";
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
  # binding="strong"によって他のルールで追加されたフォントよりも優先されます。
  generateMatchEntry = originalFamily: targetFamily: ''
    <match target="pattern">
      <test name="family"><string>${originalFamily}</string></test>
      <edit name="family" binding="strong" mode="assign"><string>${targetFamily}</string></edit>
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
  fonts = {
    fontconfig = {
      allowBitmaps = false; # ビットマップフォントを無効化します。
      defaultFonts = {
        sansSerif = [
          "Fira Sans" # Mozillaが開発したサンセリフ書体。
          "BIZ UDGothic" # 日本語のユニバーサルデザインのゴシック体。
          "emoji" # 絵文字向けフォールバック。
        ];
        serif = [
          "Noto Serif" # GoogleとAdobeが開発したセリフ体。
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
      # `localConf`は`/etc/fonts/local.conf`に書き出され、`51-local.conf`によりpriority 51で評価されます。
      # priority 51は`60-latin.conf`より前ですが、`binding="strong"`により後続の弱バインディングを上書きできます。
      localConf = generateOverrideConf fontAliases;
    };

    # 表示されてあまり困らないフォントパッケージを雑に追加します。
    packages = with pkgs; [
      biz-ud-gothic
      fira
      firge-font
      firge-nerd-font
      hackgen-nf-font
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
    ];
  };
}
