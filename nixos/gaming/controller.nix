{ pkgs, ... }: {
  hardware.xpadneo.enable = true;
  environment.systemPackages = with pkgs; [
    dualsensectl
  ];
  # Switch Proコントローラはsteam-hardware経由で設定済みなので設定不要。
  # ジョイコンの合体などが必要になったらjoycondが必要。
}
