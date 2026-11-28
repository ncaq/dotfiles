{
  inputs,
  localLib,
  overlays,
  system,
  username,
  ...
}:
let
  inherit (localLib) importDirModules nixpkgsConfig;
  inherit (inputs)
    home-manager
    nixpkgs
    nixpkgs-unstable
    ;
  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
    overlays = overlays ++ [
      inputs.nix-on-droid.overlays.default
    ];
  };
in
inputs.nix-on-droid.lib.nixOnDroidConfiguration {
  inherit pkgs;
  modules = [
    {
      # nix-on-droidが受け付ける最新のバージョン。
      system.stateVersion = "24.05";
      # 常に有効にしておく機能をランタイムでも有効化。
      nix.extraOptions = ''
        experimental-features = flakes nix-command
      '';
      environment = {
        # Android端末はほぼ携帯端末なので、
        # コンフリクトしたファイルを処理するのには手間がかかるので、
        # 自動でリネームするのは合理的。
        etcBackupExtension = ".bak";
        # Tailscale前提のDNS設定。
        # MagicDNSのリゾルバはIPv4とIPv6の両方のアドレスで待ち受けているので、
        # IPv6を先に並べてIPv4を予備にする。
        # 検索ドメインはtailnetの名前から組み立てる(`lib/tailnet.nix`)。
        # nix-on-droid自身が公開DNSを書いた`text`を定義していて、
        # `text`で書くと行が連結されるので、`source`で丸ごと置き換える。
        etc."resolv.conf".source = pkgs.writeText "resolv.conf" ''
          search ${localLib.tailnet}
          nameserver fd7a:115c:a1e0::53
          nameserver 100.100.100.100
        '';
      };
      # Nix-on-Droid特有のAndroid連携設定。
      android-integration = {
        am.enable = true;
        termux-open.enable = true;
        termux-open-url.enable = true;
        termux-reload-settings.enable = true;
        termux-setup-storage.enable = true;
        termux-wake-lock.enable = true;
        termux-wake-unlock.enable = true;
        xdg-open.enable = true;
      };
      # Termuxのターミナルのフォント設定は一つのファイルしか指定できない。
      terminal.font = "${pkgs.firge-nerd-font}/share/fonts/firge-nerd/FirgeNerdConsole-Regular.ttf";
      # Androidホストのタイムゾーンは自動的に引き継がれないようなので明示的に設定。
      time.timeZone = "Asia/Tokyo";
      user = {
        # 既定は`"nix-on-droid"`だが他の環境と揃える。
        # 変わるのは`/etc/passwd`の名前と`USER`で、uidとホームディレクトリはAndroidが決めたまま。
        userName = username;
        shell = "${pkgs.zsh}/bin/zsh";
      };
      # 今後home-managerに設定を委任。
      home-manager = {
        backupFileExtension = "hm-bak";
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          inherit
            importDirModules
            localLib
            inputs

            username
            ;
          pkgs-unstable = import nixpkgs-unstable {
            inherit system overlays;
            config = nixpkgsConfig;
          };
          isTermux = true; # アプリとしてはnix-on-droidですがランタイム的にはTermuxの方が妥当な名前。
          isWSL = false;
        };
        sharedModules = [
          inputs.sops-nix.homeManagerModules.sops
        ];
        config = ../home;
      };
    }
  ];
  # set path to home-manager flake
  home-manager-path = home-manager.outPath;
}
