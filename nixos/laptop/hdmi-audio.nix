{ pkgs, ... }:
{
  # 外部ディスプレイ(テレビなど音声出力を持つもの)にHDMI接続したとき、
  # 音声出力のデフォルトをそのHDMI sinkへ自動で切り替える。
  # 内蔵スピーカーの`priority.session`が`1000`なので、
  # HDMIをそれより高い値にする。
  # GPUの音声コントローラは複数のHDMIピンを持ちsinkも複数現れるが、
  # WirePlumberはport availability(EDIDから取得するELD)を考慮するため、
  # 実際にディスプレイが接続され音声出力可能なピンだけがデフォルトに選ばれる。
  # 音声情報を持たない映像のみのモニタではsinkのportが利用不可のままになり、
  # デフォルトには選ばれないので意図しない切り替えは起きない。
  #
  # `node.name`のHDMI(大文字)はこのラップトップのUCM(HiFi)プロファイル形式
  # `alsa_output.pci-xxxx.HiFi__HDMI1__sink`に対応する。
  services.pipewire.wireplumber.configPackages = [
    (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/52-hdmi-priority.conf" ''
      monitor.alsa.rules = [
        {
          matches = [
            {
              "node.name" = "~alsa_output.*HDMI.*"
            }
          ]
          actions = {
            update-props = {
              "priority.session" = 1200
              "priority.driver" = 1200
            }
          }
        }
      ]
    '')
  ];
}
