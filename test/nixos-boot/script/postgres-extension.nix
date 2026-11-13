# `postgresExtension`で宣言した拡張が実際に作られることを確認します。
# `CREATE EXTENSION`は`postgresql-setup`がsuperuserで実行しますが、
# CIの評価チェックはtoplevelの評価だけなので、
# `lib.mkAfter`で継ぎ足したスクリプトの構文やpsqlの呼び出しの誤りを検出できず、
# 実機へ適用して初めて失敗します。
#
# `postgresql-ready.service`は接続の受け付けまでしか保証せず、
# setupの完了をホスト側から観測するunitも無いため、
# 拡張が現れるまでリトライで待ちます。
#
# ホストにはpsqlが無いので、
# コンテナへ入れてあるPostgreSQLパッケージのpsqlをホスト側から直接使います。
{ lib, config, ... }:
let
  postgresExtensions = config.postgresExtension or { };
  psql = lib.getExe' config.containers.postgresql.config.services.postgresql.finalPackage "psql";
in
lib.optionalString (postgresExtensions != { }) (
  # python
  ''
    machine.wait_for_unit("postgresql-ready.service")
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (
      db:
      lib.concatMapStrings (
        ext: # python
        ''
          machine.wait_until_succeeds(
              "runuser -u postgres --"
              " ${psql} -h /run/postgresql -d '${db}'"
              " -tAc \"SELECT 1 FROM pg_extension WHERE extname='${ext}'\""
              " | grep -q 1"
          )
        ''
      )
    ) postgresExtensions
  )
)
