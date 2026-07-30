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
{ lib, config, ... }:
let
  # コンテナ内から見える出力ディレクトリ。
  # ncaqがseminar上で見るパスと揃えて分かりやすくする。
  outputDir = "/mnt/chihiro/comfyui-output";
  # コンテナ専用CIFSマウントのホスト側パス。
  # 親ディレクトリを0700にしてホストの一般ユーザから隠す。
  hostMountParent = "/run/comfyui-cifs";
  hostMountPoint = "${hostMountParent}/output";
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
        # wantedByは設定しない。
        # `container@comfyui`のRequiresMountsForが必要時にpullする。
        # コンテナが停止して誰も必要としなくなったら自動でアンマウントする。
        unitConfig.StopWhenUnneeded = true;
        what = "//seminar/chihiro/comfyui-output";
        where = hostMountPoint;
        type = "cifs";
        options = lib.concatStringsSep "," [
          # 認証。`nixos/native-linux/cifs.nix`と同じ資格情報を使う。
          "credentials=${config.sops.templates."cifs-credentials".path}"
          # コンテナのUIDはpickで毎起動変わるため、
          # 誰でも書けるモードにしてUID非依存で書き込めるようにする。
          # このマウントは0700の親ディレクトリで隠されているので、
          # ホストの一般ユーザからはアクセスできない。
          "dir_mode=0777"
          "file_mode=0666"
          # セキュリティ
          "nodev"
          "noexec"
          "nosuid"
          # パフォーマンス
          "noatime"
          # SMBダイアレクトはcifs.nixと同じ理由でSMB3.0以上を明示する。
          "vers=3"
        ];
        mountConfig = {
          TimeoutSec = 30;
        };
      }
    ];
    # extraFlagsのbind mountはbindMountsと違いRequiresMountsForが自動付与されないため、
    # 明示的に指定してコンテナ起動時にCIFSマウントを引き込む。
    # マウント失敗時はコンテナも起動しない。
    services."container@comfyui".unitConfig.RequiresMountsFor = [ hostMountPoint ];
    tmpfiles.rules = [
      "d ${hostMountParent} 0700 root root - -"
      "d ${hostMountPoint} 0700 root root - -"
    ];
  };
}
