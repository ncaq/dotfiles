{ pkgs, ... }:
{
  services.postgresql = {
    # 雑に使えるサーバグローバルのPostgreSQLサーバを有効にしておきます。
    enable = true;
    # PostgreSQLのバージョンによって`dataDir`などが変更されます。
    # `stateVersion`依存でPostgreSQLのバージョンは定まります。
    # しかし忘れて全体をアップデートして壊れたりするのが嫌なので明示的に指定しておきます。
    # JITコンパイラは必要かわかりませんが、単純なクエリには使われないらしくデメリットが薄いそうなので、雑に有効にしておきます。
    package = pkgs.postgresql_17_jit;
    # サービス側で追加する方が良いかもしれませんが、
    # ここでデータベース一覧をまとめるメリットもあるのでこちらでの定義を選択します。
    ensureDatabases = [
      "atticd"
      "forgejo"
    ];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
    ];
  };
}
