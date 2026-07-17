# ComfyUIの出力画像をseminarのchihiro共有へ直接保存するための設定。
#
# コンテナはファイルシステム隔離されているので、
# ホストの`/mnt/chihiro`をbind mountで見せた上で、
# ComfyUIの`--output-directory`で出力先を切り替える。
#
# `/mnt/chihiro`のCIFSマウントはuid=1000(ncaq),gid=100(users)の見せ方なので、
# コンテナ内のcomfyui(uid=500)はグループ経由で書き込む。
# グループ書き込みを許可する`dir_mode=0775,file_mode=0664`は、
# `nixos/native-linux/cifs.nix`のマウントオプション側で設定している。
_:
let
  outputDir = "/mnt/chihiro/comfyui-output";
in
{
  containers.comfyui = {
    # NixOSコンテナモジュールがhostPathに`RequiresMountsFor`を自動付与するため、
    # コンテナ起動時に`mnt-chihiro.mount`が引き込まれ、
    # マウント失敗時はコンテナも起動しない。
    bindMounts.${outputDir} = {
      hostPath = outputDir;
      isReadOnly = false;
    };
    config = {
      # CIFSマウントのgid=100(users)でグループ書き込みするために所属させる。
      users.users.comfyui.extraGroups = [ "users" ];
      services.comfyui.extraArgs = [
        "--output-directory"
        outputDir
      ];
      # comfyui-nixモジュールは`ProtectSystem=strict`で、
      # `ReadWritePaths`にdataDirしか含めないため出力先を追加する。
      systemd.services.comfyui.serviceConfig.ReadWritePaths = [ outputDir ];
    };
  };
}
