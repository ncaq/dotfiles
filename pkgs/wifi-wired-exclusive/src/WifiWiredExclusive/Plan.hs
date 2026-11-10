-- | デバイスの状態から、WiFiへ行う操作を決める。
--
-- 有線(Ethernet)接続中はWiFiの接続だけを切り、WiFiラジオはオンのまま維持する。
-- `nmcli radio wifi off`のようにラジオごと切ると、
-- 有線を抜いたときにスキャンからやり直しになり再接続が遅くなる。
-- `nmcli device disconnect`ならバックグラウンドスキャンが継続するため、
-- 有線を抜いた直後でもキャッシュ済みのスキャン結果で素早くWiFiへ繋ぎ直せる。
module WifiWiredExclusive.Plan
  ( plan
  ) where

import Himari
import WifiWiredExclusive.Device (Device (..))
import WifiWiredExclusive.DeviceState (DeviceState (..))
import WifiWiredExclusive.DeviceType (DeviceType (..))
import WifiWiredExclusive.Operation (Operation (..))

-- | 全デバイスの状態から、行う操作を順に並べる。
plan :: [Device] -> [Operation]
plan devices = concatMap operations (filter ((== Wifi) . (.deviceType)) devices)
 where
  -- 物理有線が1つでも繋がっているか。
  wired = any (\device -> device.deviceType == Ethernet && device.state == Connected) devices
  operations device
    | wired = case device.state of
        -- 有線接続中はWiFiが繋がっていれば接続だけ切る。
        -- 既に切れているデバイスへの切断はエラーになるので、状態で分ける。
        Connected -> [Disconnect device.name]
        Connecting -> [Disconnect device.name]
        _ -> []
    | otherwise =
        -- 有線が無ければ、切断で抑止された自動接続を解除してWiFiへ繋ぎ直す。
        EnableAutoconnect device.name : case device.state of
          -- 接続処理中に重ねて接続を要求すると、
          -- 完了待ちで90秒ブロックし、デバイスを中間状態に留めて無限ループになる。
          -- 完全に切れている時だけ繋ぎ直す。
          Disconnected -> [Connect device.name]
          _ -> []
