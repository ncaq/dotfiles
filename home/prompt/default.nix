# LLMで利用するプロンプトを連結して提供するモジュール。
{
  lib,
  inputs,
  ...
}:
let
  # 指定ディレクトリ群の直下にある全ての.mdファイルをreadFileした文字列リストを返す。
  # 手動で並べると追加時に書き漏れが起きやすいため、
  # ディレクトリから自動収集する用途で使う。
  # 引数の順序がそのまま結果の順序になる。
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
in
{
  options.prompt = {
    chatAssistant = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "通常のチャット向けのカスタムプロンプトを連結したテキスト";
    };
    codingAgent = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "コーディングエージェント向けのカスタムプロンプトを連結したテキスト";
    };
  };

  config = {
    prompt = {
      chatAssistant = lib.concatStringsSep "\n---\n" (
        readMdFiles [
          ./assistant
          ./output
          ./environment
          ./user
        ]
        ++ [
          (builtins.readFile "${inputs.www-ncaq-net}/site/about.md")
          (builtins.readFile "${inputs.www-ncaq-net}/site/entry/2025-12-28-14-43-14.md") # 現在の自分の決済方法
        ]
      );
      # codingAgentのcontextは貴重なので、
      # chatAssistantより厳選して少なめにします。
      # プログラミングに直接関係ない情報は省きます。
      codingAgent = lib.concatStringsSep "\n---\n" (readMdFiles [
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
