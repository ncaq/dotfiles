{ pkgs, config, ... }:
{
  home = {
    packages = with pkgs; [
      python3Packages.huggingface-hub # `hf`コマンド
    ];
    # `hf auth login`を手動で実行する代わりに、
    # sops-nixが復号したトークンファイルを直接読ませます。
    # `huggingface_hub`は、
    # 環境変数`HF_TOKEN`、
    # 環境変数`HF_TOKEN_PATH`が指すファイル、
    # の順にトークンを探すため、
    # パスだけを環境変数に置けばトークン自体をプロセス環境に晒さずに済みます。
    # 書き込み権限を持つトークンを使うのは対話的に操作する`hf`コマンドだけにして、
    # エージェント経由で動くMCPサーバには`mcp.nix`でread-onlyトークンを渡します。
    sessionVariables.HF_TOKEN_PATH = config.sops.secrets."huggingface/dotfiles".path;
  };
  # Hugging Faceのアクセストークンをsops-nixで管理します。
  # シークレットファイルは
  # `sops secrets/huggingface.yaml`
  # で編集してください。
  # 形式:
  # token:
  #   dotfiles: hf_xxxxxxxxxxxxxxxxxxxxx
  #   read-only: hf_xxxxxxxxxxxxxxxxxxxxx
  sops.secrets."huggingface/dotfiles" = {
    sopsFile = ../../secrets/huggingface.yaml;
    key = "token/dotfiles";
    mode = "0400";
  };
}
