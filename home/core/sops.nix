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
    home.activation.sops-nix = lib.mkForce (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Termux環境では`$XDG_RUNTIME_DIR`が設定されていませんが、
        # `sops-install-secrets`は`UserMode`で`$XDG_RUNTIME_DIR`を参照するため、
        # ダミー値を設定します。
        echo "=== sops-nix debug ==="
        echo "common.conf before sops-install-secrets:"
        cat "${cfg.gnupg.home}/common.conf" 2>&1 || echo "no common.conf"
        echo "public-keys.d exists:" && ls -la "${cfg.gnupg.home}/public-keys.d/" 2>&1 || echo "no public-keys.d"
        ${cfg.gnupg.package}/bin/gpg --homedir "${cfg.gnupg.home}" --list-secret-keys 2>&1 || echo "gpg --list-secret-keys FAILED"
        echo "=== end sops-nix debug ==="
        export XDG_RUNTIME_DIR="${cfg.defaultSecretsMountPoint}"
        export SOPS_GPG_EXEC="${cfg.gnupg.package}/bin/gpg"
        $DRY_RUN_CMD ${sops-install-secrets}/bin/sops-install-secrets -ignore-passwd ${manifest}
      ''
    );
  })
]
