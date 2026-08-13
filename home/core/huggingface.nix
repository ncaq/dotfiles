{ pkgs, config, ... }:
{
  home = {
    packages = with pkgs; [
      python3Packages.huggingface-hub # `hf`コマンド
    ];
    sessionVariables = {
      # 起動のたびにPyPIへ新しいバージョンが無いか問い合わせるのを止めます。
      # nixpkgsが固定したバージョンを使うため`hf update`は実行できず、
      # 更新を促されても取れる行動がありません。
      HF_HUB_DISABLE_UPDATE_CHECK = "1";
      # `hf auth login`を手動で実行する代わりに、
      # sops-nixが復号したトークンファイルを直接読ませます。
      # `huggingface_hub`は、
      # 環境変数`HF_TOKEN`、
      # 環境変数`HF_TOKEN_PATH`が指すファイル、
      # の順にトークンを探すため、
      # パスだけを環境変数に置けばトークン自体をプロセス環境に晒さずに済みます。
      #
      # 渡すのは書き込み権限を持つトークンです。
      # `home.sessionVariables`はログインセッション配下の全プロセスに継承されるので、
      # 自分で対話的に叩く`hf`だけでなく、
      # エージェントが起動する`hf`もこのトークンを使います。
      # `hf-cli` skillは`hf upload`や`hf jobs run`をエージェントに案内するため、
      # 誤操作や課金の余地は残ります。
      # 書き込みが必要になるのは自分の対話的な操作なので、
      # 到達範囲を狭めるより実態を把握しておく方を選びます。
      # なお`mode = "0400"`の読み取り専用ファイルを指すため、
      # skillが案内する`hf auth login`や`hf auth logout`は失敗します。
      HF_TOKEN_PATH = config.sops.secrets."huggingface/dotfiles".path;
      # Xetストレージからの転送並列度を上げます。
      # メモリと帯域を多く使う代わりに大きなファイルのダウンロードが速くなります。
      # 旧来の`HF_HUB_ENABLE_HF_TRANSFER`はhf_transfer自体が使われなくなり、
      # こちらが後継として案内されています。
      HF_XET_HIGH_PERFORMANCE = "1";
    };
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
