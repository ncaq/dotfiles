{
  lib,
  pkgs,
  config,
  ...
}:
let
  backlog-mcp-server = pkgs.callPackage ../../pkgs/backlog-mcp-server.nix { };
  mackerel-mcp-server = pkgs.callPackage ../../pkgs/mackerel-mcp-server.nix { };
  # リモートのHTTP MCPサーバにはファイルベースのシークレットを渡せる`env`が使えません。
  # 代わりにClaude Codeの`headersHelper`から呼び出して、
  # 接続時にsops-nixが復号したトークンを読み出しBearerヘッダを組み立てます。
  # トークンをプロセス環境や`.mcp.json`に置かずに済みます。
  # 401/403が返った時もClaude Codeがヘルパーを再実行するので、
  # OAuthのように認証が切れて再ログインを求められることがありません。
  mkBearerAuthHeader =
    name: tokenFile:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ jq ];
      text = ''
        token_file=${lib.escapeShellArg tokenFile}
        if [[ ! -r "$token_file" ]]; then
          printf '%s: %s を読み込めませんでした\n' ${lib.escapeShellArg name} "$token_file" >&2
          exit 1
        fi
        # トークンは`--rawfile`でjqに直接読ませます。
        # `--arg`はコマンドライン引数として渡すため、
        # jqの実行中は`/proc/<pid>/cmdline`から同一ホストの他プロセスに読めてしまいます。
        # ファイル末尾の改行はsopsが付けるので落とします。
        #
        # 空のトークンはjqの中で弾きます。
        # そのまま通すと`Authorization: Bearer `という壊れたヘッダを出してしまい、
        # Claude Code側では原因の分かりにくい401として現れるためです。
        jq -n --rawfile token "$token_file" '
          ($token | rtrimstr("\n")) as $trimmed
          | if $trimmed == ""
            then error("トークンが空です")
            else { Authorization: "Bearer \($trimmed)" }
            end
        '
      '';
    };
  # Cloudflareの統合MCPサーバはデフォルトではOAuthで認証しますが、
  # OAuthだとブラウザでの再ログインを割と頻繁に求められて煩わしいです。
  # 公式がCI/CD向けにAPIトークンのBearer認証をサポートしているので、
  # sops-nixで管理するAPIトークンをヘッダで渡します。
  cloudflare-mcp-auth-header =
    mkBearerAuthHeader "cloudflare-mcp-auth-header"
      config.sops.secrets."cloudflare/mcp-api-token".path;
  # 渡すのは`huggingface.nix`と同じ書き込み可能なトークンです。
  # 以前はエージェントの誤操作を防ぐためにread-onlyのトークンを分けていましたが、
  # `HF_TOKEN_PATH`が`home.sessionVariables`にある以上、
  # ログインセッション配下で動くエージェントは`hf`コマンド経由で書き込み可能なトークンに到達できます。
  # MCPサーバだけをread-onlyにしても実効的な分離にならないため、
  # 見かけ上の安全を作るのをやめて実態に揃えます。
  hf-mcp-server-auth-header =
    mkBearerAuthHeader "hf-mcp-server-auth-header"
      config.sops.secrets."huggingface/dotfiles".path;
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
        # 公式ドキュメント検索だけの`docs.mcp.cloudflare.com`ではなく、
        # 自分のアカウントのリソースも扱える統合サーバを使います。
        # 統合サーバにも`docs`ツールがあるのでドキュメント検索は引き続き可能です。
        # 個別の旧サーバ群(observabilityやbindingsなど)は非推奨になっています。
        url = "https://mcp.cloudflare.com/mcp";
        headersHelper = lib.getExe cloudflare-mcp-auth-header;
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
      mackerel = {
        # 自宅インフラの監視に使っているMackerelを常に見られるようにします。
        command = lib.getExe mackerel-mcp-server;
        env = {
          MACKEREL_APIKEY.file = config.sops.secrets."mackerel-mcp-server/api-key".path;
        };
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
    # Cloudflare MCP Server用のAPIトークンをsops-nixで管理します。
    # 他のCloudflareのトークンと同じファイルにまとめています。
    # シークレットファイルは
    # `sops secrets/cloudflare.yaml`
    # で編集してください。
    # 形式:
    # mcp_api_token: your-api-token
    # トークンはCloudflareダッシュボードのAPIトークン作成画面で作ります。
    # アカウントトークンの場合はアカウントIDの自動検出のために
    # Account Resources: Readの権限が必要です。
    # Client IP Address Filteringを有効にしたトークンは非対応です。
    "cloudflare/mcp-api-token" = {
      sopsFile = ../../secrets/cloudflare.yaml;
      key = "mcp_api_token";
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
    # Mackerel MCP Server用のAPIキーをsops-nixで管理します。
    # シークレットファイルは
    # `sops secrets/mackerel-mcp-server.yaml`
    # で編集してください。
    # 形式:
    # api-key: your-api-key
    "mackerel-mcp-server/api-key" = {
      sopsFile = ../../secrets/mackerel-mcp-server.yaml;
      key = "api-key";
      mode = "0400";
    };
  };
}
