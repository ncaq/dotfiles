{
  config,
  lib,
  pkgs,
  ...
}:
let
  # flakeに定義された全nixosConfigurationsとhomeConfigurationsの閉包を、
  # GCから保護するGC rootを登録するスクリプト。
  #
  # セルフホストランナーはこのホストのnix storeを共有していますが、
  # `nix build`のresultリンクはephemeralなランナーコンテナ内にあるため、
  # ジョブ終了後は他ホスト向けの閉包(特にbulletの巨大なモデルファイル)を守るrootが残りません。
  # そのままnix-gcに回収されると、
  # 次のCIで巨大なパスをHDD RAID上のキャッシュから取得し直すことになります。
  # https://github.com/ncaq/dotfiles/issues/1535
  #
  # デプロイ時に配置される`/etc/nixos-flake`(nix-daemon.nix参照)から、
  # 全nixosConfigurationsのtoplevelとhome-managerの閉包をビルドして、
  # `--out-link`でGC rootとして保持します。
  # デプロイ済みのflakeを参照するため作業ツリーには依存しません。
  # どちらの属性集合も動的に列挙するため、
  # flakeへ構成を追加するとこのスクリプトも自動で追従します。
  # `nixOnDroidConfigurations`は列挙の対象に含めていません。
  # QEMUエミュレーション経由のビルドが遅く、
  # モデルファイルのような巨大なパスも含まれないためです。
  nix-gc-root-hosts = pkgs.writeShellApplication {
    name = "nix-gc-root-hosts";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      failed=0
      roots=()

      build() {
        local name="$1" installable="$2"
        roots+=("$name")
        if ! nix build "$installable" --out-link "$STATE_DIRECTORY/$name"; then
          echo "failed to build $installable" >&2
          failed=1
        fi
      }

      # 一覧の取得に失敗した場合はここで中断します。
      # 誤って後段のクリーンアップで既存のrootを消してしまわないようにするためです。
      hostNames=$(nix eval --json /etc/nixos-flake#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')
      homeSystems=$(nix eval --json /etc/nixos-flake#homeConfigurations --apply builtins.attrNames | jq -r '.[]')

      while IFS= read -r host; do
        build "nixos-$host" "/etc/nixos-flake#nixosConfigurations.$host.config.system.build.toplevel"
      done <<<"$hostNames"
      while IFS= read -r system; do
        build "home-manager-$system" "/etc/nixos-flake#homeConfigurations.$system.activationPackage"
      done <<<"$homeSystems"

      # flakeから消えた構成のrootを削除して、
      # 不要になった閉包をいつまでも保持し続けないようにします。
      shopt -s nullglob
      for link in "$STATE_DIRECTORY"/*; do
        name=$(basename "$link")
        keep=0
        for root in "''${roots[@]}"; do
          if [[ "$name" == "$root" ]]; then
            keep=1
            break
          fi
        done
        if [[ "$keep" == 0 ]]; then
          rm -- "$link"
        fi
      done

      exit "$failed"
    '';
  };
in
{
  systemd.services.nix-gc-root-hosts = {
    description = "Register Nix GC roots for all hosts' closures";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe nix-gc-root-hosts;
      StateDirectory = "nix-gc-root-hosts";
      # キャッシュが切れているとビルドに長時間かかることがあります。
      TimeoutStartSec = "8h";
    };
  };

  # nix-gcの実行前にGC rootを更新します。
  # root更新が失敗してもGC自体は実行させたいのでrequiresではなくwantsにします。
  systemd.services.nix-gc = {
    wants = [ "nix-gc-root-hosts.service" ];
    after = [ "nix-gc-root-hosts.service" ];
  };
}
