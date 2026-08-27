{
  lib,
  pkgs-unstable,
  config,
  codingAgentWorkDirFullPath,
  ...
}:
let
  # 接続するOllamaのホストと、そのホストのアクセラレータ。
  # bulletを名指しするのはGPU推論を使いたいためで、
  # 他のホストのOllamaはコーディングに使える速度が出ない。
  #
  # 2つを組にして置くのは、
  # contextの長さもモデルの一覧もアクセラレータから引くためです。
  # ホスト名の隣で決めておかないと、
  # 接続先を変えた時に片方だけが古いまま残り、
  # CPUのホストへCUDAの前提を宣言したproviderが静かに生まれます。
  ollamaHostName = "bullet";
  ollamaAccelerator = "cuda";

  # OllamaのTailscale Service経由のURL。
  ollamaBaseUrl = import ../../lib/ollama-tailscale-url.nix { inherit lib; } {
    hostName = ollamaHostName;
    tailnet = import ../../lib/tailnet.nix;
  };
  # providerへ載せるモデル。
  # 接続先のgeneralに定義しているものだけを載せます。
  # freedom側のモデルはコーディング向きではないためです。
  #
  # `limit`を書かないとOpenCodeは接続先が扱える長さを知りません。
  # models.devに載っていない素のproviderなので、
  # 他所から引いてくる当てもありません。
  # `context`はモデルが一度に保持できるトークンの総数で、
  # `output`は1回の応答の上限です。
  # 配分の考え方は`lib/ollama-context.nix`にあります。
  ollamaModels =
    let
      ollamaContext = import ../../lib/ollama-context.nix;
      budget = ollamaContext.budget ollamaContext.length.${ollamaAccelerator};
      modelNames = import ../../lib/ollama-model-names.nix;
    in
    lib.genAttrs modelNames.${ollamaAccelerator}.general (_: {
      limit = {
        inherit (budget) context output;
      };
    });
in
{
  programs.opencode = {
    enable = true;
    # コーディングエージェントは更新が早くサーバも最新バージョンを要求しがちなのでunstableを使います。
    package = pkgs-unstable.opencode;
    # グローバル指示です。
    # `~/.config/opencode/AGENTS.md`に配置されます。
    context = config.prompt.codingAgent;
    # `mcp.nix`と連携します。
    enableMcpIntegration = true;
    # `~/.config/opencode/opencode.json`に配置されます。
    settings = {
      # パッケージはNixで管理しているため自己アップデートは無効にします。
      autoupdate = false;
      model = "github-copilot/gpt-5.6-sol";
      small_model = "github-copilot/gpt-5-mini";
      lsp = true;
      # bulletのOllamaをOpenAI互換APIの素のproviderとして登録します。
      # `ollama launch opencode`のハーネス経由ではなく通常のAPI呼び出しで利用します。
      # Tailscale ServiceのURLを使うことでbullet以外のクライアントからも同じ設定で使えます。
      provider.ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (bullet)";
        options.baseURL = "${ollamaBaseUrl}/v1";
        models = ollamaModels;
      };
      permission.external_directory = {
        # Claude Codeと同じ追加ディレクトリを許可します。
        "${codingAgentWorkDirFullPath}**" = "allow";
        "/nix/store/**" = "allow";
        "~/dotfiles/**" = "allow";
      };
    };
    # `home/linked/.claude/keybindings.json`と共通の操作へ寄せます。
    tui.keybinds = {
      editor_open = "ctrl+l";
      messages_undo = "ctrl+/";
      session_interrupt = "ctrl+g";
      input_submit = "meta+return";
      input_newline = "return";
      history_previous = "up,ctrl+t";
      history_next = "down,ctrl+n";
      "dialog.select.prev" = "up,ctrl+t";
      "dialog.select.next" = "down,ctrl+n";
      "dialog.select.submit" = "meta+return";
      "prompt.autocomplete.prev" = "up,ctrl+t";
      "prompt.autocomplete.next" = "down,ctrl+n";
      "prompt.autocomplete.hide" = "ctrl+g";
      "prompt.autocomplete.select" = "meta+return";
      # tmuxのスクロールキーと同じ操作でメッセージをスクロールできるようにします。
      # tmuxはalternate screen上のペインではこれらのキーをアプリに透過してくるので、
      # OpenCode側で同じ挙動を割り当てて通常のターミナルとスクロール操作を揃えます。
      messages_line_up = "shift+up";
      messages_line_down = "shift+down";
      messages_page_up = "pageup,shift+left";
      messages_page_down = "pagedown,shift+right";
      # shift+矢印のデフォルトは入力欄のテキスト選択ですが、
      # スクロールキーとして使うため無効化します。
      input_select_up = "none";
      input_select_down = "none";
      input_select_left = "none";
      input_select_right = "none";
    };
  };
}
