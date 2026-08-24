# LLM向けのスキルやそれに近いものの読み込みを行います。
# Claude Code向けにはmarketplace経由ではなくビルド済みプラグインを直接読み込むことで、
# ヘルパースクリプトまでnixで管理できます。
# 詳細はモジュール提供側の定義を参照してください。
{ inputs, ... }:
{
  imports = [
    inputs.konoka.homeModules.default
    inputs.blue-prompt.homeModules.default
  ];

  konoka = {
    claude-code.enable = true;
    opencode.enable = true;
  };

  blue-prompt = {
    claude-code.enable = true;
    # konokaのhaskell-tasuke:himariとrole-play:himariのスキル名が、
    # OpenCodeのフラットなスキル名前空間で衝突してビルドが失敗するため、
    # 応急処置として無効にしています。
    opencode.enable = false;
  };
}
