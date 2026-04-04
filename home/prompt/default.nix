# LLMで利用するプロンプトを連結して提供するモジュール。
{
  lib,
  inputs,
  ...
}:
let
  programmingPrompts = [
    (builtins.readFile ./programming/command.md)
    (builtins.readFile ./programming/nix-command.md)
    (builtins.readFile ./programming/github.md)
    (builtins.readFile ./programming/naming-rule.md)
    (builtins.readFile ./programming/use-error-info.md)
    (builtins.readFile ./programming/check-job.md)
    (builtins.readFile ./programming/test.md)
  ];
  codingAgentPrompts = [
    (builtins.readFile ./coding-agent/workspace.md)
  ];
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
      chatAssistant = lib.concatStringsSep "\n" (
        [
          (builtins.readFile ./assistant/language.md)
          (builtins.readFile ./assistant/form.md)
          (builtins.readFile ./assistant/markdown.md)
          (builtins.readFile ./assistant/communication-guideline.md)
          (builtins.readFile ./assistant/persona.md)
          (builtins.readFile ./environment/software.md)
          (builtins.readFile ./environment/hardware.md)
          (builtins.readFile ./user/decision-style.md)
          (builtins.readFile ./user/disclosure-policy.md)
          (builtins.readFile ./user/house.md)
          (builtins.readFile ./user/job.md)
          (builtins.readFile ./user/tech-context.md)
          (builtins.readFile "${inputs.www-ncaq-net}/site/about.md")
          (builtins.readFile "${inputs.www-ncaq-net}/site/entry/2025-12-28-14-43-14.md") # 現在の自分の決済方法
        ]
        ++ programmingPrompts
      );
      # codingAgentのcontextは貴重なので、
      # chatAssistantより厳選して少なめにします。
      # プログラミングに直接関係ない情報は省きます。
      codingAgent = lib.concatStringsSep "\n" (
        [
          (builtins.readFile ./assistant/language.md)
          (builtins.readFile ./assistant/form.md)
          (builtins.readFile ./assistant/markdown.md)
          (builtins.readFile ./environment/software.md)
        ]
        ++ programmingPrompts
        ++ codingAgentPrompts
      );
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
