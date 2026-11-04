{ pkgs, ... }:
{
  services.printing = {
    enable = true;
    # プリンタはIPP Everywhereのドライバレス接続で使っているので、
    # hplipのようなメーカー固有のドライバは入れない。
    drivers = with pkgs; [ cups-filters ];
    # ネットワーク上のプリンタの発見はcupsd自身のDNS-SD対応で足りる。
    # cups-browsedは過去にリモートコード実行の入口になった経緯があるので動かさない。
    browsed.enable = false;
  };
}
