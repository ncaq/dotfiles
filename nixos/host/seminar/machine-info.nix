{ ... }:
{
  # hostnamectlでのChassisタイプをserverに設定
  environment.etc."machine-info".text = ''
    CHASSIS=server
  '';
}
