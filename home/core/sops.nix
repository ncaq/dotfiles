{
  config,
  lib,
  pkgs,
  isTermux,
  ...
}:
let
  cfg = config.sops;
  sops-install-secrets = cfg.package;

  # manifestを生成。
  # sops-nixモジュールと同じロジック。
  # Termux環境ではsystemdサービスが使えないため、
  # activation hookで直接実行する必要があります。
  manifestFor =
    suffix: secrets: templates:
    pkgs.writeTextFile {
      name = "manifest${suffix}.json";
      text = builtins.toJSON {
        secrets = builtins.attrValues secrets;
        templates = builtins.attrValues templates;
        secretsMountPoint = cfg.defaultSecretsMountPoint;
        symlinkPath = cfg.defaultSymlinkPath;
        inherit (cfg) keepGenerations;
        gnupgHome = cfg.gnupg.home;
        inherit (cfg.gnupg) sshKeyPaths;
        ageKeyFile = cfg.age.keyFile;
        ageSshKeyPaths = cfg.age.sshKeyPaths;
        placeholderBySecretName = cfg.placeholder;
        userMode = true;
        logging = {
          keyImport = builtins.elem "keyImport" cfg.log;
          secretChanges = builtins.elem "secretChanges" cfg.log;
        };
      };
    };

  manifest = manifestFor "" cfg.secrets cfg.templates;
in
lib.mkMerge [
  {
    # home-manager用sops-nixの設定
    sops.gnupg.home = "${config.home.homeDirectory}/.gnupg";
    # sops-nix home-managerモジュールは`gnupg.home`が設定されていると、
    # pinentryのGUIダイアログを前提として`WantedBy=graphical-session-pre.target`をデフォルトにします。
    # https://github.com/Mic92/sops-nix/pull/346
    # しかしヘッドレスサーバではこのtargetに到達せず、
    # サービスが起動しないままになるため`default.target`に強制上書きします。
    # 副鍵にパスフレーズを設定していないためpinentryは不要です。
    # またデスクトップ機でもグラフィカルシェル無しで起動する場合に備えてこの上書きは全ホスト適用します。
    systemd.user.services.sops-nix.Install.WantedBy = lib.mkForce [ "default.target" ];
  }
  (lib.mkIf isTermux {
    # Termux環境では`$XDG_RUNTIME_DIR`が設定されていないため、
    # シークレットの配置場所を明示的に指定します
    sops.defaultSecretsMountPoint = "${config.xdg.stateHome}/sops-nix/secrets.d";
  })
  (lib.mkIf (isTermux && cfg.secrets != { }) {
    # Termux環境ではsystemdサービスの代わりにactivation hookで直接復号化します。
    # sops-nixモジュールの`home.activation.sops-nix`は`systemctl`を呼び出しますが、
    # Termux環境ではsystemdが動作しないため、
    # 直接`sops-install-secrets`を実行します。
    # `lib.mkForce`で元のactivation hookを上書きします
    # 実際のパスはmanifestで明示的に指定済み。
    # GPGの鍵インポート完了後に`sops-install-secrets`を実行します。
    # `importGpgKeys`への依存を明示しないと、
    # `writeBoundary`直後に`sops-nix`が先行してGPG未準備の状態で復号化が失敗します。
    home.activation.sops-nix = lib.mkForce (
      lib.hm.dag.entryAfter [ "writeBoundary" "importGpgKeys" ] ''
        # Termux環境では`$XDG_RUNTIME_DIR`が設定されていませんが、
        # `sops-install-secrets`は`UserMode`で`$XDG_RUNTIME_DIR`を参照するため、
        # ダミー値を設定します。
        export XDG_RUNTIME_DIR="${cfg.defaultSecretsMountPoint}"
        export SOPS_GPG_EXEC="${cfg.gnupg.package}/bin/gpg"
        $DRY_RUN_CMD ${sops-install-secrets}/bin/sops-install-secrets -ignore-passwd ${manifest}
      ''
    );
  })
]
