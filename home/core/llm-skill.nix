# LLM向けのスキルやそれに近いものの読み込みを行います。
# Claude Code向けにはmarketplace経由ではなくビルド済みプラグインを直接読み込むことで、
# ヘルパースクリプトまでnixで管理できます。
# 詳細はモジュール提供側の定義を参照してください。
{ inputs, ... }:
{
  imports = [ inputs.konoka.homeModules.default ];

  konoka = {
    claude-code.enable = true;
    opencode.enable = true;
  };
}
