/**
  NixOS Testのマシンがブートするかを確認するときのVMの設定。
  テスト時には機能しないものなどを無効化したりモックにしたりします。
*/
{
  pkgs,
  lib,
  config,
  options,
  username,
  ...
}:
lib.mkMerge [
  {
    # NixOS Testでいくらリソースを使っていいかの設定。
    # CIで実行する時はサーバのコンテナ単位でリソースを制限しているので、
    # 多めに設定していても破綻はしませんが、
    # リソース制限をわかりやすくするためにこちらでも記述しておきます。
    virtualisation = {
      # CPUは奪い合っても良いので割り当て可能スレッド数を割り当てます。
      cores = config.local.cpuBudgetThreads;
      memorySize = 4 * 1024; # 4GB。並列に動かすことを考えて控えめにします。
    };

    # NixOSテストフレームワークがrootに`hashedPasswordFile`を自動設定するため、
    # user.nixで設定している`hashedPassword`と重複定義の警告が出ます。
    # テスト環境ではrootパスワードは不要なので`hashedPassword`を無効化して警告を除去します。
    users.users.root.hashedPassword = lib.mkForce null;

    # diskoのデバイス定義を無効化。
    # VMではvirtualisationモジュールがファイルシステムを管理します。
    disko.devices = lib.mkForce { };

    # sopsをモックにして必要とするサービスを誤魔化します。
    sops = {
      validateSopsFiles = false;
      gnupg = {
        home = lib.mkForce "/run/sops-dummy";
        sshKeyPaths = lib.mkForce [ ];
      };
    };
    home-manager.sharedModules = lib.mkAfter [
      { sops.validateSopsFiles = false; }
    ];
    systemd.services.sops-install-secrets.serviceConfig = lib.mkForce {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/true";
      RemainAfterExit = true;
    };

    # テスト環境ではネットワーク通信の認証をさせないのですが、
    # その場合Tailscale関係サービスが起動しようとかなり粘ってしまい、
    # テストが無意味に遅くなるので無効化しておきます。
    services.tailscale.enable = lib.mkForce false;
    home-manager.users.${username}.services.trayscale.enable = lib.mkForce false;
  }
  # ホスト限定オプションなので分岐して無効化。
  (lib.optionalAttrs (options ? custom.tailscale-exit-node.enable) {
    custom.tailscale-exit-node.enable = lib.mkForce false;
  })
]
