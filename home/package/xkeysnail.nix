{
  config,
  pkgs,
  lib,
  isWSL,
  ...
}:
lib.mkIf (!isWSL) {
  home.packages = with pkgs; [
    xkeysnail
  ];

  home.activation.cloneXkeysnailConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/.xkeysnail" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.xkeysnail.git "${config.home.homeDirectory}/.xkeysnail"
    else
      echo "Info: ${config.home.homeDirectory}/.xkeysnail already exists, skipping clone"
    fi
  '';

  systemd.user.services.xkeysnail = {
    Unit = {
      Description = "xkeysnail";
    };
    Service = {
      # デバイスが初期化される前に起動してエラーになることへのワークアラウンド。
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
      Restart = "on-failure";
      ExecStart = "${pkgs.xkeysnail}/bin/xkeysnail --quiet %h/.xkeysnail/config.py";
      Environment = [
        "DISPLAY=:0"
        "PATH=${pkgs.xkeysnail}/bin:${pkgs.python3}/bin"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
