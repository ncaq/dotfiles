# GitHub ActionsのランナのVMを起動する前に、VMへ渡すストアの状態を作り直すコマンド。
#
# 同じディレクトリの`module.nix`が定義する`<VMの名前>-store.service`から呼ばれる。
#
# ```console
# github-runner-store <Nixのデータベースのディレクトリ> <写しを置くディレクトリ> <書き込み用の層のイメージ>
# ```
#
# VMはホストのストアを読み取り専用で共有して、書き込みはVMだけが持つ層のイメージへ入れます。
# 起動のたびに以下をします。
#
# - 書き込み用の層のイメージを消す。
#   無ければmicrovm.nixが起動の前に空のものを作るので、前のジョブが書いたものが残りません
# - 前の起動の時のデータベースの写しを消して、今のホストのデータベースの写しを取り直す。
#   動いているデータベースをそのままコピーすると書き込みの途中を拾うことがあるので、
#   SQLiteのバックアップの機能で一貫した状態を取ります
#
# sqlite3コマンドは既定ではロックを待たずに`database is locked`で失敗します。
# VMごとのサービスが同時に動くと、他に接続の無いデータベースを同時に開くことになり、
# 片方がそのロックに当たります。
# 失敗するとVMが起動できなくなるので、ロックが外れるのを待たせます。
#
# ファイルを消してsqlite3を呼ぶだけなので、シェルスクリプトにしています。
{
  coreutils,
  sqlite,
  localLib,
  testers,
  writeShellApplication,
}:
writeShellApplication {
  name = "github-runner-store";
  runtimeInputs = [
    coreutils
    sqlite
  ];
  text = ''
    nix_db_dir=$1
    store_dir=$2
    overlay_image=$3
    rm --force "$overlay_image" "$store_dir/db.sqlite"
    sqlite3 -cmd ".timeout 60000" "$nix_db_dir/db.sqlite" ".backup '$store_dir/db.sqlite'"
  '';
  # 他のユーザのイメージを消せることと、隔離の中からデータベースを読めることは、
  # 実際のユニットを動かさないと確かめられない。
  passthru.tests.nixos = import ./nixos-test.nix { inherit localLib testers; };
}
