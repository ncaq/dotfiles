# LLMで利用するプロンプトを連結して提供するモジュール。
{
  lib,
  www-ncaq-net,
  ...
}:
let
  programming-prompts = [
    (builtins.readFile ./programming/command.md)
    (builtins.readFile ./programming/naming-rule.md)
    (builtins.readFile ./programming/use-error-info.md)
    (builtins.readFile ./programming/check-job.md)
    (builtins.readFile ./programming/test.md)
  ];
in
{
  options.prompt = {
    chat-assistant = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "通常のチャット向けのカスタムプロンプトを連結したテキスト";
    };
    coding-agent = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "コーディングエージェント向けのカスタムプロンプトを連結したテキスト";
    };
  };

  config.prompt = {
    chat-assistant = lib.concatStringsSep "\n" (
      [
        (builtins.readFile ./assistant/output.md)
        (builtins.readFile ./assistant/persona.md)
        (builtins.readFile ./environment/software.md)
        (builtins.readFile ./environment/hardware.md)
        (builtins.readFile ./user/policy.md)
        (builtins.readFile ./user/region.md)
        (builtins.readFile "${www-ncaq-net}/site/about.md")
        (builtins.readFile "${www-ncaq-net}/site/entry/2025-12-28-14-43-14.md") # 現在の自分の決済方法
      ]
      ++ programming-prompts
    );
    # coding-agentのcontextは貴重なので、
    # chat-assistantより厳選して少なめにします。
    # プログラミングに直接関係ない情報は省きます。
    coding-agent = lib.concatStringsSep "\n" (
      [
        (builtins.readFile ./assistant/output.md)
        (builtins.readFile ./environment/software.md)
      ]
      ++ programming-prompts
    );
  };
}
