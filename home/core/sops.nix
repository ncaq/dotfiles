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

  # manifestを生成
  # sops-nixモジュールと同じロジック
  # Termux環境ではsystemdサービスが使えないため、
  # activation hookで直接実行する必要があります
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

  script = lib.getExe (
    pkgs.writeShellApplication {
      name = "sops-nix-user-termux";
      text = ''
        export SOPS_GPG_EXEC="${cfg.gnupg.package}/bin/gpg"
        ${sops-install-secrets}/bin/sops-install-secrets -ignore-passwd ${manifest}
      '';
    }
  );
in
lib.mkMerge [
  {
    # home-manager用sops-nixの設定
    sops.gnupg.home = "${config.home.homeDirectory}/.gnupg";
  }
  (lib.mkIf isTermux {
    # Termux環境では$XDG_RUNTIME_DIRが設定されていないため、
    # シークレットの配置場所を明示的に指定する
    sops.defaultSecretsMountPoint = "${config.xdg.stateHome}/sops-nix/secrets.d";
  })
  (lib.mkIf (isTermux && cfg.secrets != { }) {
    # Termux環境では、systemdサービスの代わりにactivation hookで直接復号化
    # sops-nixモジュールのhome.activation.sops-nixはsystemctlを呼び出すが、
    # Termux環境ではsystemdが動作しないため、直接sops-install-secretsを実行する
    # lib.mkForceで元のactivation hookを上書きする
    home.activation.sops-nix = lib.mkForce (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${script}
      ''
    );
  })
]
