{ lib, ... }:
{
  # CIランナーのコンテナからプライベートなネットワークへの転送を落とす。
  #
  # ランナーの中ではリポジトリのワークフローが持ち込んだコードが動く。
  # 必要な通信先はGitHubやcache.nixos.orgのようなインターネットと、
  # ホスト上のCaddy(ホスト側のvethアドレスの443)だけで、
  # 後者はFORWARDではなくINPUTで届くのでここの影響を受けない。
  #
  # 何もしないとホストのFORWARDが通してしまう先は以下で、
  # どれもCIジョブに触らせる理由が無い。
  #
  # - 自宅LAN(ルータの管理画面や他のホストの有線側)
  # - tailnet(seminarの身分でtailscale0から出ていく)
  # - 他のコンテナのゲスト側アドレス
  #
  # 送信元アドレスではなくインターフェイス名で見るのは、
  # コンテナのrootは自分のnetns内で任意の送信元アドレスを名乗れるため。
  # vethの名前はIFNAMSIZの制限で`ve-github-rRhHH`のように短縮されるが、
  # 接頭辞は残るのでワイルドカードで拾える。
  #
  # NATモジュールが`internalInterfaces`からのacceptを同じチェインに足すので、
  # それより前に評価されるように`mkBefore`で先頭へ置く。
  networking.firewall.extraForwardRules = lib.mkBefore ''
    iifname "ve-github-*" ip daddr {
      10.0.0.0/8,
      172.16.0.0/12,
      192.168.0.0/16,
      100.64.0.0/10,
      169.254.0.0/16
    } drop comment "CI runner containers must not reach LAN, tailnet or other containers"
    iifname "ve-github-*" ip6 daddr {
      fc00::/7,
      fe80::/10
    } drop comment "CI runner containers must not reach local IPv6 networks"
  '';
}
