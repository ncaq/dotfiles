{ pkgs, ... }: {
  home.packages = with pkgs; [
    python3Packages.huggingface-hub # `hf`コマンド
  ];
}
