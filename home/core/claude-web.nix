{
  config,
  ...
}:
{
  home.file = {
    # 通常版Claudeに必要なカスタムプロンプトを配置します。
    # ここに`CLAUDE_WEB.md`ファイルを配置する意味はまったくないのですが、
    # 公式に配置する場所がないので関連する場所ということで間借りさせてもらいます。
    # 更新されたら配置したあと手動で設定画面にコピペします。
    # Claude Codeと同じ`.claude`ディレクトリに配置します。
    ".claude/CLAUDE_WEB.md".text = config.prompt.chatAssistant;
  };
}
