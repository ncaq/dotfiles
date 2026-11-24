# 全ホストのクロージャをGC rootとして登録するサービスを、ストアのGCの前に挟むNixOSモジュール。
#
# 読み込んだホストでは、定期のタイマーがGCではなくこのサービスを起動します。
# 順序がコマンドの役割と対になっているので、パッケージの隣に置いています。
# 使う側(`nixos/host/seminar/nix-gc-root-hosts.nix`)は読み込むだけです。
# テスト(`nixos-test.nix`)もこのモジュールだけを読むので、ホストの構成に依存しません。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hardening = import ../../lib/systemd-hardening.nix;
  # サービス名はユニット属性名・StateDirectory・CacheDirectoryなど各所で使うため、
  # リネーム時の取りこぼしが起きないよう一箇所から導出します。
  serviceName = "nix-gc-root-hosts";
  # 稼働中のsystemdと同じパッケージの`systemctl`。
  systemctl = lib.getExe' config.systemd.package "systemctl";
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
  # 中身は隣の`package.nix`にあります。
  nix-gc-root-hosts = pkgs.nix-gc-root-hosts.override {
    nix = config.nix.package;
  };
in
{
  # 負荷を見て見送る振る舞いと、後ろに続くGCは、ストアの手入れのモジュールが定義しています。
  imports = [ ../nix-store-maintenance/module.nix ];

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
      # GCと同じように、負荷が高い時は始めずに時間を置いて確かめ直します。
      serviceConfig =
        hardening.network
        // config.local.nixStoreMaintenance.retryServiceConfig
        // {
          Type = "oneshot";
          ExecStart = lib.getExe nix-gc-root-hosts;
          # root更新が終わったらGCを起動します。
          # 先頭の`+`はサンドボックスの外で動かす指定で、`systemctl`がsystemdと話せるようにします。
          # GCの終わりは待ちません。
          ExecStartPost = "+${systemctl} start --no-block nix-gc.service";
          StateDirectory = serviceName;
          CacheDirectory = serviceName;
          # キャッシュが効いている時は数分で終わります。
          # キャッシュが切れているとビルドに時間がかかるので余裕は持たせますが、
          # 毎日動くので、次の回に重なるほど長くは待ちません。
          # 途中で止められても、ビルドが済んだ分はストアに残って次の回に使われます。
          TimeoutStartSec = "2h";
          # 定期のウォームアップに緊急性はないため、
          # 同居するCIや公開サービスへリソースを譲ります。
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
        };
    };

  };

  # GCの前にGC rootを更新するために、定期のタイマーはGCではなくroot更新を起動します。
  # root更新が終わった時にGCを起動するので、順番はroot更新、GC、最適化です。
  #
  # root更新をGCの`Wants`にして連れて起動させることはしません。
  # GCが負荷を見て起動し直すたびに、root更新も動き直して負荷を上げるからです。
  #
  # root更新は全ホストをビルドするので、終わった直後は負荷が高くなります。
  # GCは最初の検査では始まらず、5分後の再試行から始まるのが普通です。
  #
  # 以下の日は、root更新がGCを起動しないのでGCも動きません。
  #
  # - 負荷の検査が上限の回数まで通らずに、root更新が見送られた日
  # - root更新の本体が失敗したか、タイムアウトした日
  systemd.timers.nix-gc.timerConfig.Unit = "${serviceName}.service";
}
