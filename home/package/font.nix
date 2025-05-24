{ pkgs, lib, ... }:
let
  fontAliases = {
    "DejaVu Sans" = "sans-serif";
    "Liberation Mono" = "monospace";
    "Liberation Sans" = "sans-serif";
  };
  generateMatchEntry = originalFamily: targetFamily: ''
    <match target="pattern">
      <test name="family"><string>${originalFamily}</string></test>
      <edit name="family" binding="same" mode="assign"><string>${targetFamily}</string></edit>
    </match>
  '';
  generateOverrideConf =
    aliases:
    let
      header = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
      '';
      body = lib.concatStringsSep "\n" (lib.mapAttrsToList generateMatchEntry aliases);
      footer = '''</fontconfig>'';
    in
    header + "\n" + body + "\n" + footer;
in
{
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      sansSerif = [ "monospace" ]; # 私は通常の英文でも等幅フォントの方が読みやすいと感じる
      serif = [
        "Noto Serif CJK JP"
        "emoji"
      ];
      monospace = [
        "HackGen Console NF"
        "emoji"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  home.packages = with pkgs; [
    hackgen-nf-font
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji
  ];

  # GNU/Linux環境の標準的なフォントを指定してくるwebサイト向けにこちらの指定するフォントを使わせたい。
  xdg.configFile."fontconfig/conf.d/90-override.conf".text = generateOverrideConf fontAliases;
}
