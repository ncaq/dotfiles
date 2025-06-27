{
  pkgs,
  lib,
  ...
}:
let
  # 必要なパッケージ
  runtimeDeps = with pkgs; [
    coreutils
    gnugrep
    inotify-tools
    iputils
    systemd
    util-linux
  ];

  # grive2にsystemdユニットを追加するオーバーレイ
  grive2WithSystemd = pkgs.grive2.overrideAttrs (oldAttrs: {
    postInstall =
      (oldAttrs.postInstall or "")
      + ''
        # systemdユニットファイルをインストール
        install -Dm644 $src/systemd/grive-timer@.timer $out/lib/systemd/user/grive-timer@.timer

        # .inファイルをPATHを追加してインストール
        cat > $out/lib/systemd/user/grive-timer@.service <<EOF
        [Unit]
        Description=Google drive sync
        After=network-online.target

        [Service]
        ExecStart=$out/lib/grive/grive-sync.sh sync "%i"
        Environment="PATH=$out/bin:${lib.makeBinPath runtimeDeps}"
        EOF

        cat > $out/lib/systemd/user/grive-changes@.service <<EOF
        [Unit]
        Description=Google drive sync (changed files)

        [Service]
        ExecStart=$out/lib/grive/grive-sync.sh listen "%i"
        Type=simple
        Restart=always
        RestartSec=30
        Environment="PATH=$out/bin:${lib.makeBinPath runtimeDeps}"

        [Install]
        WantedBy=default.target
        EOF

        # grive-sync.shスクリプトをインストール
        install -Dm755 $src/systemd/grive-sync.sh $out/lib/grive/grive-sync.sh
      '';
  });
in
{
  home.packages = [
    grive2WithSystemd
    pkgs.inotify-tools # grive-changes@.serviceに必要
  ];

  # systemdユニットファイルをユーザー設定にリンク
  xdg.configFile = {
    "systemd/user/grive-timer@.service".source =
      "${grive2WithSystemd}/lib/systemd/user/grive-timer@.service";
    "systemd/user/grive-timer@.timer".source =
      "${grive2WithSystemd}/lib/systemd/user/grive-timer@.timer";
    "systemd/user/grive-changes@.service".source =
      "${grive2WithSystemd}/lib/systemd/user/grive-changes@.service";
  };

  # 起動時の有効化・開始
  home.activation.setupGrive2Services = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GOOGLE_DRIVE_DIR="$HOME/GoogleDrive"
    ESCAPED_DIR=$(${pkgs.systemd}/bin/systemd-escape "$GOOGLE_DRIVE_DIR")
    if [ -f "$GOOGLE_DRIVE_DIR/.grive" ]; then
      echo "Enabling grive2 services for $GOOGLE_DRIVE_DIR"
      # systemdの再読み込み
      ${pkgs.systemd}/bin/systemctl --user daemon-reload
      # タイマーの有効化と開始
      ${pkgs.systemd}/bin/systemctl --user enable "grive-timer@$ESCAPED_DIR.timer" 2>/dev/null || true
      ${pkgs.systemd}/bin/systemctl --user start "grive-timer@$ESCAPED_DIR.timer"
      # ファイル変更検知サービスの有効化と開始
      ${pkgs.systemd}/bin/systemctl --user enable "grive-changes@$ESCAPED_DIR.service" 2>/dev/null || true
      ${pkgs.systemd}/bin/systemctl --user start "grive-changes@$ESCAPED_DIR.service"
    else
      echo "Grive2 not initialized. Run 'grive -a' in $GOOGLE_DRIVE_DIR first."
      echo "After initialization, run 'home-manager switch' again to enable services."
    fi
  '';
}
