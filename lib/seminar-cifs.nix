/**
  seminarのchihiro共有をCIFSマウントするための共通定義。

  `nixos/native-linux/cifs.nix`(/mnt/chihiroの常用マウント)と、
  `nixos/host/bullet/comfyui/dir.nix`(ComfyUIコンテナ専用マウント)で共用して、
  片方だけ更新される事故を防ぐ。
*/
{ pkgs }:
let
  hardening = import ./systemd-hardening.nix;
  # seminarのSMBポートへ実際にTCP接続できるまで待つスクリプト。
  # `network-online.target`や`tailscale-online.service`はどちらも
  # 「seminarに到達できる」ことまでは保証しないため、
  # マウント前に実到達性を確認する必要がある。
  waitForSeminar = pkgs.writeShellApplication {
    name = "wait-for-seminar";
    runtimeInputs = with pkgs; [
      bash
      coreutils
    ];
    text = ''
      until timeout 5 bash -c ': < /dev/tcp/seminar/445'; do
        sleep 2
      done
    '';
  };
in
{
  inherit waitForSeminar;
  # マウントの見せ方(uid/dir_modeなど)に依存しない基本のマウントオプション。
  baseMountOptions = credentialsPath: [
    # 認証
    "credentials=${credentialsPath}"
    # セキュリティ
    "nodev"
    "noexec"
    "nosuid"
    # パフォーマンス
    "noatime"
    # SMBダイアレクトを明示的に指定。
    # 未指定だとkernelが`No dialect specified on mount`の警告を出す。
    # `vers=3`はSMB3.0以上を意味し、ネゴシエーションで3.x系の最新版が選択される。
    # SMB1/SMB2系を排除しつつ、将来のマイナーバージョン更新にも自動追従する。
    "vers=3"
  ];
  # マウント失敗時にOnFailureから起動するリトライサービスを生成する。
  # seminarへの到達性が回復するまで待ってから対象のmountユニットを再起動する。
  # `name`はスクリプトのderivation名に使うので英数字とハイフンだけにする
  # (mountユニット名はパスのエスケープでバックスラッシュを含むことがあるため分ける)。
  mkRetryService =
    {
      name,
      description,
      mountUnit,
    }:
    {
      inherit description;
      unitConfig = {
        # mount側のStartLimitだけに停止保証を頼らない。
        # mountがstart-limit-hitで拒否された場合にOnFailureが再発火するかは、
        # systemdのバージョンで挙動が異なるため(systemd/systemd#33710)、
        # 再発火する環境でもこのサービス自身の起動制限でループを確実に打ち切る。
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };
      # 到達性確認のTCP接続(AF_INET/AF_INET6)と、
      # systemctlのプライベートソケット(AF_UNIX)だけあれば動く。
      # 書き込み先はないのでProtectSystem=strictのままで良い。
      serviceConfig = hardening.network // {
        Type = "oneshot";
        TimeoutStartSec = 600;
        ExecStart = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "retry-${name}";
            runtimeInputs = with pkgs; [
              coreutils
              systemd
              waitForSeminar
            ];
            # 失敗直後の即時再試行は同じ理由で失敗しやすいので少し置く。
            text = ''
              sleep 10
              wait-for-seminar
              systemctl restart "${mountUnit}"
            '';
          }
        );
      };
    };
}
