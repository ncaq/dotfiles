/**
  seminarのchihiro共有をCIFSマウントするための共通定義。

  `nixos/native-linux/cifs.nix`(/mnt/chihiroの常用マウント)と、
  `nixos/host/bullet/comfyui/dir.nix`(ComfyUIコンテナ専用マウント)で共用して、
  片方だけ更新される事故を防ぐ。
*/
{ pkgs }:
{
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
}
