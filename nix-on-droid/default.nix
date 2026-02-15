{
  importDirModules,
  inputs,
  nixpkgsConfig,
  overlays,
  system,
  username,
  ...
}:
let
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
      # nix-on-droidのセットアップ時の最新バージョン。
      system.stateVersion = "24.05";
      # 常に有効にしておく機能をランタイムでも有効化。
      nix.extraOptions = ''
        experimental-features = flakes nix-command
      '';
      environment = {
        # Android端末はほぼ携帯端末なのでコンフリクトしたファイルを処理するのには手間がかかるので合理的。
        etcBackupExtension = ".bak";
        # Tailscale前提のDNS設定。
        etc."resolv.conf".source = ./resolv.conf;
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
        # `userName`はnix-on-droidでread-onlyで`"nix-on-droid"`固定のため設定不可。
        # 以下のコミットで変更可能なようになるようですがまだリリースされていません。
        # [allow both group and username to be changed](https://github.com/nix-community/nix-on-droid/commit/010aa48cf613ce3b4a0ed57457920f66ff3239f8)
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
