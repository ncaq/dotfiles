# bulletをWake-on-LANのmagic packetで起動できるようにする、受け取る側の設定です。
# magic packetを送る側の設定はseminarにあります。
#
# NICのWoL設定はNetworkManagerの接続プロファイルで行います。
# NixOSには`networking.interfaces.<name>.wakeOnLan`もありますが、
# あれはsystemdの`.link`ファイルを生成するもので、
# `.link`はデバイスに最初にマッチした1つだけが適用される仕様のため、
# systemd標準の`99-default.link`が持つ`NamePolicy`を打ち消して、
# NICの名前を変えてしまう危険があります。
# NetworkManagerのプロファイルは宣言的に管理しているので、
# そちらで有効化するほうが既存の管理方法とも一貫します。
#
# なおOS側の設定だけではシャットダウン状態から起動することはできません。
# NICへ待機電力を供給するようにUEFIセットアップで設定する必要があります。
# MSIのマザーボードでは概ね以下の項目が該当します。
#
# - `ErP Ready`を`Disabled`にして、電源オフ状態でもNICへ給電する
# - `Resume By PCI-E Device`を`Enabled`にして、NICからの起床を許可する
_: {
  networking.networkmanager.ensureProfiles.profiles.basic-ethernet.ethernet = {
    # NetworkManagerのkeyfileではフラグを数値で指定します。
    # 64(0x40)は`magic`を意味し、magic packetを受信した時だけ起床します。
    # ブロードキャストやunicastでも起床する設定にすると、
    # 日常的なLANの通信で意図せず起きてしまいます。
    wake-on-lan = 64;
  };
}
