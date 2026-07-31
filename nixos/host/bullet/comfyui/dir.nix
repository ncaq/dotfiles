# ComfyUIの出力画像をseminarのchihiro共有へ直接保存するための設定。
#
# コンテナはファイルシステム隔離されているので、
# CIFSマウントをbind mountで見せた上で、
# ComfyUIの`--output-directory`で出力先を切り替える。
#
# `/mnt/chihiro`本体のマウントはuid=1000(ncaq),gid=100(users)の見せ方だが、
# `privateUsers = "pick"`のコンテナからはUIDがマップされず書き込めない。
# CIFSはidmapped mountに対応していないため(kernel 6.18時点でEINVAL)、
# idmapオプションのbind mountによる解決もできない。
# そこでコンテナ専用に同じ共有のcomfyui-outputサブディレクトリを、
# 誰でも書けるモードで別マウントする。
#
# コンテナ内部でのマウント定義にはできない。
# カーネルはcifsに`FS_USERNS_MOUNT`フラグを付けていないため、
# ユーザ名前空間内からのcifsマウントはEPERMで拒否される(実機確認済み)。
# 代わりにマウントユニットをコンテナのライフサイクルに連動させる:
# `RequiresMountsFor`でコンテナ起動時にだけマウントされ、
# `StopWhenUnneeded`でコンテナ停止時に自動でアンマウントされる。
# 0700のrootディレクトリ配下に置いてホストの一般ユーザからは隠すため、
# ホスト側のセキュリティは緩まない。
# サーバ側の認証と所有権はマウント資格情報(ncaq)で決まるので、
# どのUIDで書いてもseminar上ではncaqのファイルになる。
{
  lib,
  pkgs,
  config,
  utils,
  ...
}:
let
  # コンテナ内から見える出力ディレクトリ。
  # ncaqがseminar上で見るパスと揃えて分かりやすくする。
  outputDir = "/mnt/chihiro/comfyui-output";
  # コンテナ専用CIFSマウントのホスト側パス。
  # 親ディレクトリを0700にしてホストの一般ユーザから隠す。
  hostMountParent = "/run/comfyui-cifs";
  hostMountPoint = "${hostMountParent}/output";
  mountUnit = "${utils.escapeSystemdPath hostMountPoint}.mount";
  inherit (import ../../../../lib/seminar-cifs.nix { inherit pkgs; })
    baseMountOptions
    mkRetryService
    ;
in
{
  containers.comfyui = {
    config = {
      services.comfyui.extraArgs = [
        "--output-directory"
        outputDir
      ];
      # comfyui-nixモジュールは`ProtectSystem=strict`で、
      # `ReadWritePaths`にdataDirしか含めないため出力先を追加する。
      systemd.services.comfyui.serviceConfig.ReadWritePaths = [ outputDir ];
    };
    # 誰でも書けるモードのマウントなのでidmapは不要。
    extraFlags = [ "--bind=${hostMountPoint}:${outputDir}" ];
  };
  systemd = {
    mounts = [
      {
        # 資格情報が展開されてからマウントする。
        # コンテナはソケットアクティベーションでブート後に起動するため、
        # 通常はどちらも満たされている。
        wants = [
          "seminar-online.service"
          "sops-install-secrets.service"
        ];
        after = [
          "seminar-online.service"
          "sops-install-secrets.service"
        ];
        unitConfig = {
          # wantedByは設定しない。
          # `container@comfyui`のRequiresMountsForが必要時にpullする。
          # コンテナが停止して誰も必要としなくなったら自動でアンマウントする。
          StopWhenUnneeded = true;
          # `nofail`は意図的に付けない。
          # wantedByを持たずブート時に引き込まれないため、
          # remote-fs.target経由でブートをブロックする経路がそもそもなく、
          # 失敗はコンテナの起動失敗として顕在化させて気付けるようにしたい。
          # マウント失敗時はリトライ用サービスに委ねる。
          # mountユニット自体はRestart=を持てないため、
          # 到達性を待ってから再マウントする別サービスで補う。
          OnFailure = [ "comfyui-cifs-retry.service" ];
          # リトライが恒久的な失敗(認証エラーなど)で無限ループしないよう起動回数を制限する。
          StartLimitIntervalSec = 600;
          StartLimitBurst = 5;
        };
        what = "//seminar/chihiro/comfyui-output";
        where = hostMountPoint;
        type = "cifs";
        # 認証・セキュリティ・ダイアレクトの共通部分は`lib/seminar-cifs.nix`で管理する。
        # 資格情報は`nixos/native-linux/cifs.nix`と同じものを使う。
        options = lib.concatStringsSep "," (
          baseMountOptions config.sops.templates."cifs-credentials".path
          ++ [
            # コンテナのUIDはpickで毎起動変わるため、
            # 誰でも書けるモードにしてUID非依存で書き込めるようにする。
            # このマウントは0700の親ディレクトリで隠されているので、
            # ホストの一般ユーザからはアクセスできない。
            "dir_mode=0777"
            "file_mode=0666"
          ]
        );
        mountConfig = {
          TimeoutSec = 30;
        };
      }
    ];
    services = {
      # extraFlagsのbind mountはbindMountsと違いRequiresMountsForが自動付与されないため、
      # 明示的に指定してコンテナ起動時にCIFSマウントを引き込む。
      # マウント失敗時はコンテナも起動しない。
      "container@comfyui".unitConfig.RequiresMountsFor = [ hostMountPoint ];
      # マウント失敗時にOnFailureから起動されるリトライサービス。
      # seminarへの到達性が回復するまで待ってから再マウントする。
      # 再マウント直後に誰も必要としていなければStopWhenUnneededですぐ外れるが、
      # 到達性の回復を待つ経路を作ることで、
      # seminarの一時的なダウン後に自動復旧できるようにする。
      comfyui-cifs-retry = mkRetryService {
        name = "comfyui-cifs";
        description = "Retry mounting ComfyUI CIFS output after failure";
        inherit mountUnit;
      };
    };
    tmpfiles.rules = [
      "d ${hostMountParent} 0700 root root - -"
      "d ${hostMountPoint} 0700 root root - -"
    ];
  };
}
