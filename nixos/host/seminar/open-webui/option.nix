# Open WebUIのモジュール同士が共有する値を宣言するオプション。
{ lib, ... }:
{
  options.local.openWebui.ollamaPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    default = 11434;
    description = ''
      Open WebUIがOllamaを探しに行くホスト側のポート。
      コンテナのvethのhostAddressでCaddyが待ち受けて、
      bulletとseminarのOllamaへ優先順位付きで振り分ける。
      ホストのloopbackで待つOllamaのproxyとはbindアドレスが違うので衝突しない。
    '';
  };
}
