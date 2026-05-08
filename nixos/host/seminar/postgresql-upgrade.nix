{ pkgs, ... }:
let
  # `postgresql.nix`で指定しているv17_jitと同じバージョンを参照する。
  # PostgreSQL本体はNixOS Container内で動作するため、ホストの`config.services.postgresql`は存在しない。
  oldPackage = pkgs.postgresql_17_jit;
  newPackage = pkgs.postgresql_18_jit;
in
{
  # メジャーアップグレード支援用一時モジュール。
  # `sudo upgrade-pg-cluster`で以下を一括実行する:
  #   1. クライアントコンテナ停止
  #   2. PostgreSQLコンテナ停止
  #   3. 旧クラスタにdata checksumsを有効化
  #   4. 新バージョン用データディレクトリをinitdb
  #   5. pg_upgradeで論理オブジェクトと物理ファイルを移行
  # 完了後は`postgresql.nix`の`package`を新バージョンに切替えてリビルドする。
  # アップグレード完了かつ動作安定確認後は本ファイルを削除する。
  environment.systemPackages = [
    oldPackage
    newPackage
    (pkgs.writeShellApplication {
      name = "upgrade-pg-cluster";
      runtimeInputs = with pkgs; [
        coreutils
        systemd
        sudo
      ];
      text = ''
        set -euxo pipefail

        OLDDATA=/var/lib/postgresql/${oldPackage.psqlSchema}
        NEWDATA=/var/lib/postgresql/${newPackage.psqlSchema}
        OLDBIN=${oldPackage}/bin
        NEWBIN=${newPackage}/bin

        if [ ! -d "$OLDDATA" ]; then
          echo "ERROR: $OLDDATA not found" >&2
          exit 1
        fi
        if [ -d "$NEWDATA" ]; then
          echo "ERROR: $NEWDATA already exists. Remove it before retrying." >&2
          exit 1
        fi

        # 1) クライアントコンテナを先に停止する。
        #    container@postgresql.serviceにbindsToされているため依存は自動連鎖するが、
        #    明示的に停止してログを分かりやすくする。
        systemctl stop \
          container@forgejo.service \
          container@niks3-public.service \
          container@niks3-private.service

        # 2) PostgreSQLコンテナを停止する。
        systemctl stop container@postgresql.service

        # 3) v17クラスタにdata checksumsを有効化する。
        #    v18ではdata checksumsがデフォルト有効、pg_upgradeは新旧クラスタ間で
        #    data checksums設定が一致している必要があるため事前に有効化する。
        sudo -u postgres "$OLDBIN/pg_checksums" --enable -D "$OLDDATA"

        # 4) v18の新データディレクトリを作成しinitdbする。
        #    v17クラスタとロケール・エンコーディングを揃える必要がある。
        install -d -m 0700 -o postgres -g postgres "$NEWDATA"
        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" \
          -D "$NEWDATA" \
          --encoding=UTF8 \
          --locale=ja_JP.UTF-8 \
          --data-checksums

        # 5) pg_upgradeで移行する。
        #    --linkは使わない。失敗時のロールバックを容易にするためコピー方式を選択。
        #    --jobsは並列度を最大化する。
        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir="$OLDDATA" \
          --new-datadir="$NEWDATA" \
          --old-bindir="$OLDBIN" \
          --new-bindir="$NEWBIN" \
          --jobs="$(nproc)" \
          "$@"

        echo
        echo "Upgrade completed. Next steps:"
        echo "  1. Edit nixos/host/seminar/postgresql.nix to use pkgs.postgresql_18_jit"
        echo "  2. Run: sudo nixos-rebuild switch --flake .#seminar"
        echo "  3. Run vacuumdb --all --analyze-in-stages inside container"
        echo "  4. After verification, delete $OLDDATA and remove postgresql-upgrade.nix"
      '';
    })
  ];
}
