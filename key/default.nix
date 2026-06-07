{
  # 署名と認証機能のある鍵のフィンガープリント。
  identityKey = "ACA66AB679E75544";

  # 公開鍵ファイルのパス。
  publicKeyFile = ./ncaq-public-key.asc;

  # SSH認証に使用するGPGサブキーのkeygrip。
  # `gpg --list-keys --with-keygrip`で[A]能力を持つサブキーのkeygripを確認できます。
  sshKeygrip = "29C212A380A9E2977752FA41C35A2F9BF6CA24E2"; # 認証サブキー 0xACA66AB679E75544
}
