{
  config,
  ...
}:
{
  home.file = {
    # チャット版のLLMサービスに必要なパーソナルプロンプトを配置します。
    # Claude Codeの場所にファイルを配置する意味はまったくなく不合理とまで言えますが、
    # いい感じに配置する場所がないので、
    # 関連する場所ということで間借りさせてもらいます。
    # 実害はないので整合性は妥協します。
    # 更新されたら配置したあと、
    # 自動で更新する手段のないものは手動で設定画面にコピペします。
    ".claude/CHAT_ASSISTANT.md".text = config.prompt.chatAssistant;
    ".claude/CHAT_ASSISTANT_MINI.md".source = config.prompt.chatAssistantMini;
  };
}
