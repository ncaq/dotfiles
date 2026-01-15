# LLMで利用するプロンプトを連結して提供するモジュール。
{
  lib,
  www-ncaq-net,
  ...
}:
let
  programming-prompts = [
    (builtins.readFile ./programming/command.md)
    (builtins.readFile ./programming/github.md)
    (builtins.readFile ./programming/naming-rule.md)
    (builtins.readFile ./programming/use-error-info.md)
    (builtins.readFile ./programming/check-job.md)
    (builtins.readFile ./programming/test.md)
  ];
  coding-agent-prompts = [
    (builtins.readFile ./coding-agent/workspace.md)
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

  config = {
    prompt = {
      chat-assistant = lib.concatStringsSep "\n" (
        [
          (builtins.readFile ./assistant/language.md)
          (builtins.readFile ./assistant/form.md)
          (builtins.readFile ./assistant/persona.md)
          (builtins.readFile ./environment/software.md)
          (builtins.readFile ./environment/hardware.md)
          (builtins.readFile ./user/decision-style.md)
          (builtins.readFile ./user/disclosure-policy.md)
          (builtins.readFile ./user/house.md)
          (builtins.readFile ./user/job.md)
          (builtins.readFile ./user/tech-context.md)
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
          (builtins.readFile ./assistant/form.md)
          (builtins.readFile ./environment/software.md)
        ]
        ++ programming-prompts
        ++ coding-agent-prompts
      );
    };

    # コーディングエージェント用の一時作業ディレクトリを作成します。
    # 一定期間アクセスのないファイルは自動的にクリーンアップされます。
    # `d`で指定されるデフォルトでの期間は10日間ですが、
    # コーディングエージェントの作業ディレクトリとして使う場合は、
    # 大きすぎるファイルや今のプロジェクトに関係のないファイルが大量に入ってノイズになりそうなので、
    # `D`の方を使って短めに2日間のクリーンアップを設定しています。
    # パーミッションはhome-manager側の設定なので個別のユーザが所有者になります。
    # シングルログイン前提です。
    # マルチユーザが多数ログインするような環境では適切に動作しない可能性があります。
    # `$XDG_RUNTIME_DIR`を使うのはビルド時に環境変数は確定していないので少し面倒で、
    # マルチユーザ環境に対応する必要が今のところないので対応しません。
    systemd.user.tmpfiles.rules = [
      "D /tmp/coding-agent-work 0700 - - 2d"
    ];
  };
}
