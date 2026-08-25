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
    name = serviceName;
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      failed=0
      names=()
      installables=()

      add() {
        names+=("$1")
        installables+=("$2")
      }

      # 一覧の取得に失敗した場合はここで中断します。
      # 誤って後段のクリーンアップで既存のrootを消してしまわないようにするためです。
      hostNames=$(nix eval --json /etc/nixos-flake#nixosConfigurations --apply builtins.attrNames | jq -r '.[]')
      homeSystems=$(nix eval --json /etc/nixos-flake#homeConfigurations --apply builtins.attrNames | jq -r '.[]')

      while IFS= read -r host; do
        add "nixos-$host" "/etc/nixos-flake#nixosConfigurations.$host.config.system.build.toplevel"
      done <<<"$hostNames"
      while IFS= read -r system; do
        add "home-manager-$system" "/etc/nixos-flake#homeConfigurations.$system.activationPackage"
      done <<<"$homeSystems"

      # 先に全installableを1回のnix buildへまとめて渡してウォームアップします。
      # 1つずつビルドすると評価プロセスがその都度立ち上がる上に、
      # ダウンロードとビルドが構成間で全く重なりません。
      # まとめて渡せばNixのスケジューラが構成横断で並列に処理します。
      # 失敗の検知は後段のout-linkで個別に行うため、ここでは失敗を無視します。
      nix build --keep-going --no-link "''${installables[@]}" || true

      # ウォームアップでストアに成果物が揃っているため、
      # ここの個別ビルドはout-linkを張るだけでほぼ即座に終わります。
      for i in "''${!names[@]}"; do
        if ! nix build "''${installables[$i]}" --out-link "$STATE_DIRECTORY/''${names[$i]}"; then
          echo "failed to build ''${installables[$i]}" >&2
          failed=1
        fi
      done

      # flakeから消えた構成のrootを削除して、
      # 不要になった閉包をいつまでも保持し続けないようにします。
      # `nix build`の中断などでシンボリックリンク以外の残骸が紛れ込んでいても、
      # 削除に失敗して途中終了しないよう`rm -rf`で消します。
      declare -A keep=()
      for name in "''${names[@]}"; do
        keep[$name]=1
      done
      shopt -s nullglob
      for link in "$STATE_DIRECTORY"/*; do
        name=''${link##*/}
        if [[ -z "''${keep[$name]:-}" ]]; then
          rm -rf -- "$link"
        fi
      done

      exit "$failed"
    '';
  };
in
{
  systemd.services.${serviceName} = {
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
  systemd.services.nix-gc = {
    wants = [ "${serviceName}.service" ];
    after = [ "${serviceName}.service" ];
  };
}
