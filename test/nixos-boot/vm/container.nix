{ lib, options, ... }:
{
  # cdn.ncaq.netのコンテナは、ブートテストで配信までを確かめるので起動させる必要があります。
  # `privateUsers = "pick"`ではnspawnが`/nix/store`をidmapped mountしますが、
  # テストVMの`/nix/store`はidmapped mountに対応しない9pなので起動に失敗します。
  # テストVMでだけUIDを分離しない`identity`にします。
  # 配信ディレクトリはotherのパーミッションで読むので、配信の振る舞いは変わりません。
  #
  # モジュールの形が`options`に依存すると無限再帰になるので、`config`の中で分岐します。
  config = lib.optionalAttrs (options ? local.cdnDeploy) {
    containers.cdn.privateUsers = lib.mkForce "identity";
  };
}
