{
  lib,
  pkgs,
  config,
  ...
}:
let
  backlog-mcp-server = pkgs.callPackage ../../pkgs/backlog-mcp-server.nix { };
  # Hugging FaceのMCPサーバはリモートのHTTPサーバなので、
  # ファイルベースのシークレットを渡せる`env`が使えません。
  # 代わりにClaude Codeの`headersHelper`から呼び出して、
  # 接続時にsops-nixが復号したトークンを読み出しヘッダを組み立てます。
  # トークンをプロセス環境や`.mcp.json`に置かずに済みます。
  hf-mcp-server-auth-header = pkgs.writeShellApplication {
    name = "hf-mcp-server-auth-header";
    runtimeInputs = with pkgs; [ jq ];
    text = ''
      token_file=${lib.escapeShellArg config.sops.secrets."huggingface/read-only".path}
      if ! token=$(<"$token_file"); then
        printf 'hf-mcp-server-auth-header: %s を読み込めませんでした\n' "$token_file" >&2
        exit 1
      fi
      jq -n --arg token "$token" '{ Authorization: "Bearer \($token)" }'
    '';
  };
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
      cloudflare = {
        url = "https://docs.mcp.cloudflare.com/mcp";
      };
      context7 = {
        command = lib.getExe pkgs.context7-mcp;
      };
      deepwiki = {
        url = "https://mcp.deepwiki.com/mcp";
      };
      github = {
        # GitHub公式のローカル(stdio)MCPサーバを使用します。
        # リモートHTTPサーバ(url)ではenvが使えずファイルベースのシークレットを渡せないためです。
        # nixpkgsにパッケージがあるので複雑なヘルパー認証ではなくローカル実行を選びます。
        command = lib.getExe pkgs.github-mcp-server;
        args = [ "stdio" ];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN.file = config.sops.secrets."github-mcp-server/pat".path;
        };
      };
      hf-mcp-server = {
        # `?login`を付けるとブラウザでのOAuth認証を要求されるため、
        # 認証をヘッダで済ませられる素のエンドポイントを使います。
        url = "https://huggingface.co/mcp";
        headersHelper = lib.getExe hf-mcp-server-auth-header;
      };
      mdn = {
        url = "https://mcp.mdn.mozilla.net/";
      };
      microsoft-learn = {
        url = "https://learn.microsoft.com/api/mcp";
      };
      nixos = {
        url = "https://mcp-nixos.ncaq.net/mcp";
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
    # Hugging Face MCP Serverにはread-onlyのトークンを渡します。
    # エージェント経由の操作でHubに書き込んでしまう事故を防ぐためです。
    # 書き込みも可能なトークンは`huggingface.nix`が`hf`コマンドにだけ渡します。
    "huggingface/read-only" = {
      sopsFile = ../../secrets/huggingface.yaml;
      key = "token/read-only";
      mode = "0400";
    };
  };
}
