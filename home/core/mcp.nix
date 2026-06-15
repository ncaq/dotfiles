{
  pkgs,
  config,
  lib,
  ...
}:
let
  backlog-mcp-server = pkgs.callPackage ../../pkgs/backlog-mcp-server.nix { };
in
{
  programs.mcp = {
    enable = true;
    servers = {
      backlog = {
        command = lib.getExe backlog-mcp-server;
        env = {
          BACKLOG_API_KEY.file = config.sops.secrets."backlog-mcp-server/api-key".path;
          BACKLOG_DOMAIN.file = config.sops.secrets."backlog-mcp-server/domain".path;
        };
      };
      deepwiki = {
        url = "https://mcp.deepwiki.com/mcp";
      };
      github = {
        # GitHub公式のローカル(stdio)MCPサーバを使用します。
        # リモートHTTPサーバ(url)ではenvが使えずファイルベースのシークレットを渡せないためです。
        command = lib.getExe pkgs.github-mcp-server;
        args = [ "stdio" ];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN.file = config.sops.secrets."github-mcp-server/pat".path;
        };
      };
    };
  };

  sops.secrets = {
    # Backlog MCP Server用の認証情報をsops-nixで管理します。
    # シークレットファイルは
    # `sops secrets/backlog-mcp-server.yaml`
    # で編集してください。
    # 形式:
    # api-key: your-api-key
    # domain: your-space.backlog.com
    "backlog-mcp-server/api-key" = {
      sopsFile = ../../secrets/backlog-mcp-server.yaml;
      key = "api-key";
      mode = "0400";
    };
    "backlog-mcp-server/domain" = {
      sopsFile = ../../secrets/backlog-mcp-server.yaml;
      key = "domain";
      mode = "0400";
    };
    # GitHub MCP Server用のPersonal Access Tokenをsops-nixで管理します。
    # シークレットファイルは
    # `sops secrets/github-mcp-server.yaml`
    # で編集してください。
    # 形式:
    # pat: ghp_xxxxxxxxxxxxxxxxxxxxx
    "github-mcp-server/pat" = {
      sopsFile = ../../secrets/github-mcp-server.yaml;
      key = "pat";
      mode = "0400";
    };
  };
}
