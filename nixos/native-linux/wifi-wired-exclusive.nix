{ pkgs, lib, ... }:
let
  # 有線(Ethernet)接続中はWiFiの接続だけを切り、
  # WiFiラジオはオンのまま維持する。
  # `nmcli radio wifi off`のようにラジオごと切ると、
  # 有線を抜いたときにスキャンからやり直しになり再接続が遅くなる。
  # `nmcli device disconnect`ならバックグラウンドスキャンが継続するため、
  # 有線を抜いた直後でもキャッシュ済みのスキャン結果で素早くWiFiへ繋ぎ直せる。
  #
  # NetworkManagerのdispatcherスクリプトとして、
  # デバイスの`up`/`down`イベントごとに呼ばれる。
  # `$1`がインターフェース名、`$2`がアクション。
  wifiWiredExclusive = pkgs.writeShellApplication {
    name = "wifi-wired-exclusive";
    runtimeInputs = with pkgs; [
      gnugrep
      networkmanager
    ];
    text = ''
      action="''${2:-}"
      # 接続状態が変化するup/downイベントのみ処理する。
      case "$action" in
        up | down) ;;
        *) exit 0 ;;
      esac

      # `DEVICE:TYPE:STATE`形式で全デバイスの状態を一度だけ取得する。
      # パイプで`grep -q`に繋ぐとSIGPIPEがpipefailで非ゼロ終了になりうるため、
      # 一旦変数に格納してからhere-stringで処理する。
      devices=$(nmcli -t -f DEVICE,TYPE,STATE device)

      # 物理有線が1つでもconnectedかどうか。
      # tailscaleなどのtunや仮想NICはethernet扱いされないため除外される。
      ethernet_connected() {
        grep -q '^[^:]*:ethernet:connected$' <<< "$devices"
      }

      while IFS=: read -r dev type state; do
        [ "$type" = wifi ] || continue
        if ethernet_connected; then
          # 有線接続中: WiFiが繋がっていれば接続だけ切る(ラジオはオンのまま)。
          # 既に切れているデバイスへのdisconnectはエラーになるため状態で分岐する。
          if [ "$state" = connected ] || [ "$state" = connecting ]; then
            # 切断はベストエフォート。レースで失敗しても次のイベントで再評価される。
            nmcli device disconnect "$dev" || true
          fi
        else
          # 有線が無い: disconnectで抑止された自動接続を解除し、WiFiへ繋ぎ直す。
          nmcli device set "$dev" autoconnect yes || true
          # `connecting`(接続処理中)に重複で`connect`を叩くと、
          # activated待ちで90秒ブロックし、デバイスを中間状態に留めて無限ループ化する。
          # 完全に切れている`disconnected`のときだけ繋ぎ直す。
          if [ "$state" = disconnected ]; then
            nmcli device connect "$dev" || true
          fi
        fi
      done <<< "$devices"
    '';
  };
in
{
  networking.networkmanager.dispatcherScripts = [
    {
      source = lib.getExe wifiWiredExclusive;
      type = "basic";
    }
  ];
}
