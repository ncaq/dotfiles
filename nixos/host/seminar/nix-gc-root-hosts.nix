{
  config,
  hardening,
  lib,
  pkgs,
  ...
}:
let
  # サービス名はユニット属性名・StateDirectory・CacheDirectoryなど各所で使うため、
  # リネーム時の取りこぼしが起きないよう一箇所から導出します。
  serviceName = "nix-gc-root-hosts";
  # flakeに定義された全nixosConfigurationsとhomeConfigurationsのクロージャを、
  # GCから保護するGC rootを登録するスクリプト。
  #
  # セルフホステッドランナはこのホストのnix storeにあるパスを取り直さずに使えます。
  # しかしランナは隔離された環境で動くので、
  # CIのジョブがビルドしたり取得したりしたパスは、
  # ホストのストアには残りません。
  # ホストのストアに他ホスト向けのクロージャ(特にbulletの巨大なモデルファイル)が無いと、
  # CIは巨大なパスをHDD RAID上のキャッシュから取得し直すことになります。
  # https://github.com/ncaq/dotfiles/issues/1535
  #
  # そこでデプロイ時に配置される`/etc/nixos-flake`(nix-daemon.nix参照)から、
  # 全nixosConfigurationsのtoplevelとhome-managerのクロージャをホストでビルドして、
  # `--out-link`でGC rootとして保持します。
  # デプロイ済みのflakeを参照するため作業ツリーには依存しません。
  #
  # 中身は`pkgs/nix-gc-root-hosts`にあります。
  nix-gc-root-hosts = pkgs.nix-gc-root-hosts.override {
    nix = config.nix.package;
  };
in
{
  systemd.services = {
    ${serviceName} = {
      description = "Register Nix GC roots for all hosts' closures";
      environment = {
        # `ProtectSystem = "strict"`下ではnixクライアントがstoreへ直接書けないため、
        # rootでもnix-daemon経由で操作するように固定します。
        NIX_REMOTE = "daemon";
        # `ProtectHome`でrootのホームへ書けないため、
        # nixの評価キャッシュの書き先をCacheDirectoryへ向けます。
        # `%C`はsystemdの指定子でキャッシュルート(/var/cache)に展開されます。
        XDG_CACHE_HOME = "%C/${serviceName}";
      };
      # ネットワークからflake inputsとキャッシュを取得するためnetworkプロファイルを使います。
      serviceConfig = hardening.network // {
        Type = "oneshot";
        ExecStart = lib.getExe nix-gc-root-hosts;
        StateDirectory = serviceName;
        CacheDirectory = serviceName;
        # キャッシュが切れているとビルドに長時間かかることがあります。
        TimeoutStartSec = "8h";
        # 週次のウォームアップに緊急性はないため、
        # 同居するCIや公開サービスへリソースを譲ります。
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };
    };

    # nix-gcの実行前にGC rootを更新します。
    # root更新が失敗してもGC自体は実行させたいのでrequiresではなくwantsにします。
    nix-gc = {
      wants = [ "${serviceName}.service" ];
      after = [ "${serviceName}.service" ];
    };
  };
}
