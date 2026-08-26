{
  pkgs-unstable,
  config,
  codingAgentWorkDirFullPath,
  ...
}:
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
      # URLの規則は`lib/ollama-tailscale-service.nix`と`nixos/core/tailscale.nix`が持っています。
      # モデルは`nixos/ollama/model.nix`でCUDAホストのgeneralに定義しているものだけを載せます。
      # freedom側のモデルはコーディング向きではないためです。
      provider.ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (bullet)";
        options.baseURL = "https://ollama-bullet.border-saurolophus.ts.net/v1";
        models = {
          "qwen3.8-27b-mtp:q6_k" = { };
        };
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
