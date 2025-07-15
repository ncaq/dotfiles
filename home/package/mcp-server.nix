{
  lib,
  pkgs,
  config,
  mcp-servers-nix,
  mcp-nixos,
  ...
}:
{
  # FIXME: WSLにそのまま渡すと実行できない問題を解決する。
  home.file."claude_desktop_config.json" = {
    source = mcp-servers-nix.lib.mkConfig pkgs {
      programs = {
        context7.enable = true;
        everything.enable = true;
        git.enable = true;
        github = {
          enable = true;
          passwordCommand = {
            GITHUB_PERSONAL_ACCESS_TOKEN = [
              (lib.getExe config.programs.gh.package)
              "auth"
              "token"
            ];
          };
        };
        time.enable = true;
      };
      settings.servers = {
        deepwiki = {
          url = "https://mcp.deepwiki.com/mcp";
        };
        mcp-nixos = {
          command = "${lib.getExe mcp-nixos.packages.${pkgs.system}.mcp-nixos}";
        };
      };
    };
  };
}
