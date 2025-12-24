{
  config,
  ...
}:
{
  home.file = {
    # 通常版Claudeに必要なカスタムプロンプトを配置します。
    # ここに配置する意味はまったくないのですが、
    # 公式に配置する場所がないので関連する場所ということで間借りさせてもらいます。
    "${config.xdg.configHome}/claude/CLAUDE_WEB.md".text = config.prompt.chat-assistant;
  };
}
