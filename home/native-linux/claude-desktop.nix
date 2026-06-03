{
  pkgs,
  inputs,
  ...
}:
let
  # `nodePackages.asar`が`pkgs.asar`に移動した。
  # 上流の修正PRがマージされるまでワークアラウンドで`nodePackages.asar`を差し替える。
  # https://github.com/k3d3/claude-desktop-linux-flake/pull/89
  claude-desktop =
    inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop.override
      {
        nodePackages = { inherit (pkgs) asar; };
      };
  # `claude-desktop-with-fhs`が内部で`claude-desktop`を参照しているため、
  # 上流の定義を再構築してoverride版の`claude-desktop`を取り込み直す。
  claude-desktop-with-fhs = claude-desktop.overrideAttrs (_oldAttrs: {
    runScript = "${claude-desktop}/bin/claude-desktop";
    extraInstallCommands = ''
      # Copy desktop file from the claude-desktop package
      mkdir -p $out/share/applications
      cp ${claude-desktop}/share/applications/claude.desktop $out/share/applications/

      # Copy icons
      mkdir -p $out/share/icons
      cp -r ${claude-desktop}/share/icons/* $out/share/icons/
    '';
  });
in
{
  home.packages = [ claude-desktop-with-fhs ];
}
