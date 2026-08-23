# LLMで利用するプロンプトを連結して提供するモジュール。
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # 指定ディレクトリ群の直下にある全ての.mdファイルをreadFileした文字列リストを返す。
  # 手動で並べると追加時に書き漏れが起きやすいため、
  # ディレクトリから自動収集する用途で使う。
  # 結果の順序は雑に処理しているため、
  # 順序が重要ならば手動で並べてください。
  readMdFiles =
    dirs:
    let
      readOneDir =
        dir:
        let
          mdFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
            builtins.readDir dir
          );
        in
        map (name: builtins.readFile (lib.path.append dir name)) (lib.attrNames mdFiles);
    in
    lib.concatMap readOneDir dirs;
  # 連結したプロンプト同士の境界に挟む区切り。
  # 全ての用途で同じ区切りを使うため、
  # 変更が一箇所で済むように束縛します。
  promptSeparator = "\n---\n\n";
  # AIの振る舞いそのものを決める部分で、
  # チャット向けのプロンプトはフル版もミニ版もこれを土台にします。
  assistantAndOutput = readMdFiles [
    ./assistant
    ./output
  ];
  # 文字数の上限を検査した上でテキストをファイルにします。
  # 上限を超えている場合はビルドを失敗させます。
  #
  # `builtins.stringLength`はバイト数を返すため、
  # 日本語を含むテキストでは文字数と一致せず検査に使えません。
  # UTF-8の継続バイト(0x80-0xBF)を取り除いてからバイト数を数えると、
  # ロケール設定に依存せずにコードポイント数が得られます。
  # `wc -m`はロケール依存でビルド環境では期待通りに動かないため使いません。
  writeTextWithMaxChars =
    name: maxChars: text:
    pkgs.runCommand name
      {
        inherit text maxChars;
        passAsFile = [ "text" ];
      }
      ''
        chars=$(tr -d '\200-\277' < "$textPath" | wc -c)
        if [ "$maxChars" -lt "$chars" ]; then
          echo "$name: $chars characters exceed the limit of $maxChars characters" >&2
          exit 1
        fi
        cp "$textPath" "$out"
      '';
in
{
  options.prompt = {
    chatAssistant = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "通常のチャット向けのカスタムプロンプトを連結したテキスト";
    };
    chatAssistantMini = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "通常のチャット向けだが入力できる内容が短い場合のテキストファイル、文字数上限を検査済み";
    };
    codingAgent = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "コーディングエージェント向けのカスタムプロンプトを連結したテキスト";
    };
  };

  config = {
    prompt = {
      chatAssistant = lib.concatStringsSep promptSeparator (
        assistantAndOutput
        ++ readMdFiles [
          ./environment
          ./user
        ]
        ++ [
          # 簡単な自己紹介。
          (builtins.readFile "${inputs.www-ncaq-net}/site/about.md")
          # 現在の自分の決済方法。
          (builtins.readFile "${inputs.www-ncaq-net}/site/entry/2025-12-28-14-43-14.md")
        ]
      );
      # ミニ版は文字数制限の厳しいサービスに貼り付けるためのものなので、
      # 上限を超えていないことをビルド時に保証します。
      # Grokのカスタム指示自体は12000文字入りますが、
      # Custom Agentsの指示欄は1つあたり4000文字であり、
      # 過去には全体の上限が一時的に4000文字へ縮小されたこともあるため、
      # 安全側に倒して4000文字を基準にします。
      chatAssistantMini = writeTextWithMaxChars "chat-assistant-mini.md" 4000 (
        lib.concatStringsSep promptSeparator assistantAndOutput
      );
      # codingAgentのcontextは貴重なので、
      # chatAssistantより厳選して少なめにします。
      # プログラミングに直接関係ない情報は省きます。
      codingAgent = lib.concatStringsSep promptSeparator (readMdFiles [
        ./output
        ./environment
        ./coding-agent
      ]);
    };

    # コーディングエージェント用の一時作業ディレクトリを作成します。
    # 各スキルなどは明示的にディレクトリを最初に作成するようにしていますが、
    # 念の為に事前にディレクトリを作成しておきます。
    # `%t`はユーザtmpfilesでは`$XDG_RUNTIME_DIR`に展開されます。
    # `$XDG_RUNTIME_DIR`はログアウト時に消滅するため、
    # クリーンアップ期間はデフォルトに任せます。
    # `/tmp`の方にフォールバックされたとしても、
    # デフォルトではOSが10日でクリーンアップするので、
    # 大きな問題にはなりません。
    # tmpをクリーンアップしないOSはサポート外です。
    systemd.user.tmpfiles.rules = [
      "d %t/coding-agent-work 0700 - -"
    ];
  };
}
