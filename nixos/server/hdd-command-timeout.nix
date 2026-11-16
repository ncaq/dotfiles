# HDDのコマンドのタイムアウトをカーネルの既定の30秒から180秒に延ばします。
#
# WD Blueのような家庭用のHDDはSCT ERC(TLER)に対応していないので、
# 読めないセクタがあると2分以上再試行し続けることがあります。
# カーネルがその途中の30秒で諦めてリンクをリセットすると、
# 1つのセクタが読めないだけなのに、
# RAIDからはディスクごと壊れたように見えて外されてしまいます。
# カーネルの方を長く待たせれば、
# ドライブが読めなかったと返してから、
# btrfsなどが別のコピーから直せます。
#
# SCT ERCに対応しているHDDは7秒ほどで諦めるので、
# 180秒にしても待つ時間は変わりません。
# 型番で分けずに全てのHDDを対象にします。
# SSDはこの問題が無いので対象外にします。
#
# 設定は再起動で消えるので、
# udevルールでデバイスが現れるたびに設定します。
#
# https://archive.kernel.org/oldwiki/raid.wiki.kernel.org/index.php/Timeout_Mismatch.html
{
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="sd*", ATTR{queue/rotational}=="1", ATTR{device/timeout}="180"
  '';
}
