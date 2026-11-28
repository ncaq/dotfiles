{
  lib,
  pkgs-unstable,
  config,
  codingAgentDeniedCommands,
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
  ollamaContext = import ../../lib/ollama-context.nix;
  ollamaModelNames = import ../../lib/ollama-model-names.nix;

  # Ollamaのproviderへ渡す、モデルごとのcontextの長さ。
  #
  # 引数はアクセラレータ名(`cuda`か`cpu`)で、
  # `lib/ollama-model-names.nix`のそのアクセラレータの全ての役割のモデルに`limit`を付ける。
  #
  # なぜ全ての役割に付けるか:
  #   OpenCodeは`ollama`というproviderのモデルを接続先の`/api/tags`から自動で発見するので、
  #   設定に書かなかったモデルも一覧に現れる。
  #   発見したモデルの`context`には`/api/show`の`*.context_length`を使うが、
  #   これはGGUFに書かれたモデルの最大長で、
  #   Ollamaが実際に確保する長さではない。
  #   Qwen3.8では262144と報告されるが、
  #   実際は`OLLAMA_CONTEXT_LENGTH`やモデルの`num_ctx`の長さで動いているため、
  #   `limit`を書かないとOpenCodeが使用率がまだ低いと見ている時点でcontextが溢れ、
  #   会話の圧縮も始まらない。
  #   役割を手で列挙すると、
  #   役割が増えたりモデルが別の役割へ移ったりした時に同じ不具合が黙って戻るので、
  #   表の全ての役割から組み立てる。
  #   埋め込みのモデルは`completion`の能力を持たず発見されないので、
  #   アクセラレータ別の表に無く対象にもならない。
  #
  # 役割の間でモデル名が重なると、
  # どちらの長さを使うべきか決まらないので評価を止める。
  #
  # `context`はモデルが一度に保持できるトークンの総数で、
  # `output`は1回の応答の上限。
  # 配分の考え方は`lib/ollama-context.nix`にある。
  ollamaModelLimitFor =
    accelerator:
    let
      roles = ollamaModelNames.${accelerator};
      # 翻訳のモデルだけはモデルの`num_ctx`で長さを固定している。
      lengthOf =
        role:
        if role == "translate" then ollamaContext.translateLength else ollamaContext.length.${accelerator};
      limitOf =
        contextLength:
        let
          budget = ollamaContext.budget contextLength;
        in
        {
          limit = {
            inherit (budget) context output;
          };
        };
    in
    lib.foldl' lib.attrsets.unionOfDisjoint { } (
      lib.mapAttrsToList (role: models: lib.genAttrs models (_: limitOf (lengthOf role))) roles
    );

  # 以下は`ollamaModels`の`assert`のための表明。
  checkOllamaModelLimit =
    accelerator:
    let
      roles = ollamaModelNames.${accelerator};
      result = ollamaModelLimitFor accelerator;
      allModels = lib.concatLists (lib.attrValues roles);
    in
    assert lib.assertMsg (
      lib.length allModels == lib.length (lib.unique allModels)
    ) "${accelerator}の役割の間でモデル名が重複しています";
    assert lib.assertMsg (
      lib.sort lib.lessThan (lib.attrNames result) == lib.sort lib.lessThan allModels
    ) "${accelerator}の全ての役割のモデルと`limit`を付けたモデルが一致しません";
    lib.all lib.id (
      lib.mapAttrsToList (
        role: models:
        lib.all (
          model:
          let
            # 期待値は上の`lengthOf`と`limitOf`を通さずに組み立てる。
            # 通すと、実装を取り違えても期待値も同じように取り違えて通ってしまう。
            budget = ollamaContext.budget (
              if role == "translate" then ollamaContext.translateLength else ollamaContext.length.${accelerator}
            );
          in
          lib.assertMsg (
            result.${model}.limit == {
              inherit (budget) context output;
            }
          ) "${accelerator}の${role}の${model}の`limit`が実際の長さと一致しません"
        ) models
      ) roles
    );

  # providerのモデルごとのcontextの長さ。
  #
  # 役割を手で列挙していた頃、
  # 自由度優先と翻訳のモデルに`limit`が付かず、
  # OpenCodeがGGUFの最大長を使ってcontextを溢れさせていた。
  # 役割が増えたりモデルが別の役割へ移ったりしても同じ不具合が戻らないよう、
  # 全ての役割の全てのモデルに、
  # 実際に動かしている長さが付くことを表で確かめる。
  #
  # 接続先のアクセラレータだけでなく、全てのアクセラレータで確かめる。
  # 繋いでいるのはCUDAのホストだけなので、
  # 使う分だけを見るとCPUの側の表が壊れても気付けない。
  # モデル名の表にはアクセラレータ別でない`embedding`もあるので、
  # アクセラレータの一覧は長さの表から取る。
  ollamaModels =
    assert lib.all checkOllamaModelLimit (lib.attrNames ollamaContext.length);
    ollamaModelLimitFor ollamaAccelerator;
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
      model = "github-copilot/gpt-6.1-sol";
      small_model = "github-copilot/gpt-6-luna";
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
      permission = {
        external_directory = {
          # Claude Codeと同じ追加ディレクトリを許可します。
          "${codingAgentWorkDirFullPath}**" = "allow";
          "/nix/store/**" = "allow";
          "~/dotfiles/**" = "allow";
        };
        # Claude Codeのdenyと揃えたコマンドを拒否します。
        # 最後に一致した規則が勝ち、どれにも一致しないと`ask`になるので、
        # 他のコマンドを許可する`*`を先に置きます。
        # JSONのキーは辞書順に並ぶので`*`が他の規則より先に出ます。
        bash = {
          "*" = "allow";
        }
        // builtins.listToAttrs (
          map (command: lib.nameValuePair "${command} *" "deny") codingAgentDeniedCommands
        );
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
