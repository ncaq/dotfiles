# cdn.ncaq.netのステージングから配信ディレクトリへ写す同期のNixOSモジュール。
#
# GitHub Actionsのジョブが書くステージングと、Caddyが配信するディレクトリを分けて、
# 間をこのモジュールのサービスが写します。
#
# Caddyの`file_server`はシンボリックリンクを辿り、辿らない設定もありません。
# ジョブが配信ディレクトリへ直接書けると、
# `/etc`などを指すリンクを置くだけで、
# Caddyが読めるファイルを公開できてしまいます。
# ジョブのrsyncのオプションはジョブ自身が書き換えられるので境界になりません。
# ジョブにはステージングだけを書かせて、
# 写す時にホストの側でシンボリックリンクとデバイスと特殊ファイルを捨てます。
#
# ディレクトリの所有者とユニットの隔離は、コマンドが何を捨てるかと対になっているので、パッケージの隣に置いています。
# 使う側(`nixos/host/seminar/cdn.nix`)は、どこへ置くかと誰が書くかだけを決めます。
# テスト(`nixos-test.nix`)もこのモジュールだけを読むので、ホストの構成に依存しません。
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.cdn-ncaq-net-sync;
  hardening = import ../../lib/systemd-hardening.nix;
  # 配信ディレクトリを所有して同期を行う専用のユーザ。
  syncUser = "cdn-ncaq-net";
  # 同期のサービスと、それを起動するpath unitの名前。
  syncService = "cdn-ncaq-net-sync";
in
{
  options.services.cdn-ncaq-net-sync = {
    enable = lib.mkEnableOption "cdn.ncaq.netのステージングから配信ディレクトリへの同期";
    cdnRoot = lib.mkOption {
      type = lib.types.path;
      description = "配信ディレクトリ。同期のサービスだけが書き込む。";
    };
    deployRoot = lib.mkOption {
      type = lib.types.path;
      description = "ジョブが書き込むステージングのディレクトリ。";
    };
    stagingUser = lib.mkOption {
      type = lib.types.str;
      description = ''
        ステージングへ書き込むユーザ。グループも同じ名前にする。
        このモジュールは作らないので、使う側で定義しておく。
      '';
    };
    deployPublic = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = "${cfg.deployRoot}/public";
      defaultText = lib.literalExpression ''"''${deployRoot}/public"'';
      description = "ジョブが書き込む配信コンテンツ。";
    };
    deployStamp = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      # 印は`public`の外に置きます。
      # `public`の中に置くと、ジョブのrsyncの`--delete`が書き込みの途中で印を消します。
      # 消えたこともpath unitには変化に見えるので、
      # その時点の書き込みの途中の状態を写してしまいます。
      default = "${cfg.deployRoot}/deployed";
      defaultText = lib.literalExpression ''"''${deployRoot}/deployed"'';
      description = "ジョブが配信コンテンツを書き終えた印のファイル。";
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      users.${syncUser} = {
        isSystemUser = true;
        group = syncUser;
      };
      groups.${syncUser} = { };
    };

    systemd = {
      tmpfiles.rules = [
        # ステージングのディレクトリ。
        # ジョブが`public`へrsyncで書き込んでから`deployed`をtouchします。
        #
        # ステージング自体はrootの所有にして、
        # ジョブが`public`をシンボリックリンクへ差し替えられないようにします。
        # 同期は`public/`を転送元にするので、
        # 差し替えられると`--no-links`の効かない転送元のパスでリンクが辿られます。
        # ジョブが書けるのは`public`の中と`deployed`だけです。
        "d ${cfg.deployRoot} 0755 root root -"
        "d ${cfg.deployPublic} 0755 ${cfg.stagingUser} ${cfg.stagingUser} -"
        "f ${cfg.deployStamp} 0644 ${cfg.stagingUser} ${cfg.stagingUser} -"
        # 配信ディレクトリ。
        # 同期のサービスだけが書き込み、配信する側はother権限で読み取ります。
        "d ${cfg.cdnRoot} 0755 ${syncUser} ${syncUser} -"
      ];

      services.${syncService} = {
        description = "Sync cdn.ncaq.net content from runner staging";
        serviceConfig = hardening.isolated // {
          Type = "oneshot";
          User = syncUser;
          Group = syncUser;
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.cdn-ncaq-net-sync)
            cfg.deployPublic
            cfg.deployStamp
            cfg.cdnRoot
          ];
          BindReadOnlyPaths = [ cfg.deployRoot ];
          BindPaths = [ cfg.cdnRoot ];
          ReadWritePaths = [ cfg.cdnRoot ];
        };
        # 置き場所がマウントに失敗してもブートが進むファイルシステムの上にある時に、
        # マウントされていないルートの上の空のディレクトリへ写さないように、
        # マウントを必須にします。
        unitConfig.RequiresMountsFor = [
          cfg.deployRoot
          cfg.cdnRoot
        ];
        # 同期の途中にジョブがファイルをリンクへ差し替えた時や、
        # 何かの理由で`public`自体がリンクになった時に、
        # 辿った先にホストのファイルが無いようにします。
        # ルートはExecStartのクロージャのストアのパスだけを置いたtmpfsになり、
        # 他に見えるのはステージングと配信ディレクトリだけです。
        # `/etc`や`/run`や他のストアのパスはそもそも存在しません。
        # クロージャに入るrsyncなどのパッケージは誰でも読める公開のものです。
        confinement.enable = true;
      };
      paths.${syncService} = {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = cfg.deployStamp;
      };
    };
  };
}
