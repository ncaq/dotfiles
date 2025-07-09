{
  pkgs,
  lib,
  config,
  isWSL,
  ...
}:
let
  # grive2を動かすのに必要なパッケージ。
  runtimeDeps = with pkgs; [
    coreutils
    gnugrep
    inotify-tools
    iputils
    systemd
    util-linux
  ];

  # デフォルトではscriptをインストールしないのでoverrideAttrsで追加する。
  grive2WithScript = pkgs.grive2.overrideAttrs (oldAttrs: {
    postInstall =
      (oldAttrs.postInstall or "")
      + "install -Dm755 $src/systemd/grive-sync.sh $out/lib/grive/grive-sync.sh";
  });
in
lib.mkIf (!isWSL) {
  home.packages = [
    grive2WithScript
  ];

  # 固定パスのサービスを定義することで単純化。
  systemd.user = {
    services = {
      grive-sync = {
        Unit = {
          Description = "Google drive sync";
          After = [ "network-online.target" ];
          ConditionPathExists = "%h/GoogleDrive/.grive";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${grive2WithScript}/lib/grive/grive-sync.sh sync %h/GoogleDrive";
          Environment = "PATH=${grive2WithScript}/bin:${lib.makeBinPath runtimeDeps}";
        };
      };
      grive-listen = {
        Unit = {
          Description = "Google drive listen (changed files)";
          After = [ "network-online.target" ];
          ConditionPathExists = "%h/GoogleDrive/.grive";
        };
        Service = {
          ExecStart = "${grive2WithScript}/lib/grive/grive-sync.sh listen %h/GoogleDrive";
          Type = "simple";
          Restart = "always";
          RestartSec = "30";
          Environment = "PATH=${grive2WithScript}/bin:${lib.makeBinPath runtimeDeps}";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };
    timers.grive-sync = {
      Unit = {
        Description = "Google drive sync timer";
      };
      Timer = {
        OnCalendar = "*:0/5";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };

  home.activation.createGoogleDriveDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/GoogleDrive" ]; then
      $DRY_RUN_CMD mkdir "${config.home.homeDirectory}/GoogleDrive"
    fi
  '';
}
