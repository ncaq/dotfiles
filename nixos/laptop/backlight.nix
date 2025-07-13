{ ... }:
{
  location.provider = "geoclue2";
  services.clight = {
    enable = true;
    settings = {
      dimmer = {
        # 無操作時に画面を暗くするまでの時間。
        ac_timeouts = [ ]; # AC電源時: 暗転しない
        batt_timeouts = [ (5 * 60) ]; # バッテリー時: 5分
      };
      dpms = {
        # 無操作時に画面の電源を切るまでの時間。
        ac_timeouts = [ (2 * 60 * 60) ]; # AC電源時: 2時間
        batt_timeouts = [ (10 * 60) ]; # バッテリー時: 10分
      };
    };
  };
}
