/**
  アクセラレータごとに、役割から実際のモデル名を引く表。

  型: { cuda = { general, freedom }; cpu = { general, freedom }; embedding; }

  NixOSモジュールからはこのファイルを直接importせず、
  `nixos/ollama/model.nix`がここから設定する`local.ollama.models`を参照すること。
  役割の意味と、
  自ホスト向けの`hostModels`との使い分けは`nixos/ollama/option.nix`が説明している。

  なぜNixOSのオプションではなくここに置くか:
    home-managerの設定もモデル名を必要とする。
    OpenCodeのproviderはtailnet越しにbulletのOllamaを指すため、
    載せるモデルの一覧が要る。

    home-managerからNixOSの`config`を引く`osConfig`は、
    このリポジトリの全ての構成では使えない。
    `homeConfigurations`とnix-on-droidはNixOSモジュール経由ではないので`null`になり、
    NixOSのホストでも`nixos/ollama`をimportしていないcreepとSSD0086には、
    `local.ollama`というオプション自体が存在しない。
    参照できない構成のためにリテラルのフォールバックを書くと、
    結局モデル名が二重に書かれることになる。

    素のデータをここへ置いて双方がimportすれば、
    どの構成からも同じ一覧を引ける。
*/
{
  cuda = {
    general = [
      # bulletは32GiBのVRAMに収まる範囲で汎用品質を優先して27Bのdenseを使う。
      # registryの`qwen3.8:27b-mtp-q4_K_M`ではなくHugging FaceのGGUFを自前で組むのは、
      # registryのmtp付きタグがq4_K_Mとq8_0とbf16しか無く、
      # q8_0は27GiBあってKVキャッシュを載せる余地が無いためである。
      # bulletでの実測(KVキャッシュq8_0, context 131072)では、
      # registryのq4_K_Mが23.8GiBで136.8トークン/秒に対し、
      # このq6_kは28.8GiBで106.2トークン/秒で、
      # 全層がGPUに載ったままVRAMの空きも2.5GiB残る。
      # q6_kは量子化としては事実上無損失の領域なので、
      # これ以上重みに割いても品質はほとんど変わらない。
      # 実際、一段上のq8_0は本体だけで27GiBあり、
      # contextを32768まで削ってKVを3.2GiB浮かせても載らない。
      # 逆に少しでも溢れると代償が大きく、
      # 8%がCPUへ出ただけの構成では53.5トークン/秒まで落ちた。
      "qwen3.8-27b-mtp:q6_k"
    ];
    freedom = [
      "qwen3.8-27b-heretic-rvn:q6_k"
      "mistralprism-24b:q4_k_m"
      "ms3.2-24b-magnum-diamond:q4_k_m"
    ];
  };
  cpu = {
    general = [
      # CPUの推論はメモリ帯域で頭打ちになり、
      # 1トークンごとに読み出す重みの量がそのまま速度を決める。
      # 総パラメータではなくactive parameterが効くため、
      # 同じ品質帯ならdenseよりMoEの方が圧倒的に速い。
      # seminarでの実測では9Bのdenseが約10トークン/秒に対し、
      # このactive 3BのMoEは約19トークン/秒だった。
      # CUDAのホストとqwen3.8へ揃えられないのは、
      # qwen3.8が27Bのdenseしか公開しておらずMoE版が存在しないためである。
      # GPUで効いたmtpタグはCPUでは逆効果で、
      # seminarでの実測では素のq4_K_Mの約18.9トークン/秒に対し、
      # `qwen3.6:35b-a3b-mtp-q4_K_M`は約17.0トークン/秒しか出ない。
      # 投機的デコーディングは余った演算能力を使って帯域を節約する手法だが、
      # CPUにはその余りがないため検証のコストだけが乗る。
      # 同じactive 3BのMoEである`nemotron-3.5-lightning:30b`も測ったが、
      # 約18.2トークン/秒とほぼ同速なのに、
      # Artificial Analysis Intelligence Indexは24でqwen3.6の32に届かない。
      "qwen3.6:35b-a3b"
    ];
    # 表現の自由度を優先したモデルはCPUで推論するホストには置かない。
    # seminarでの実測では24Bのdenseは約4トークン/秒しか出ず、
    # 対話を待っていられる速度ではないため、
    # ディスクとロード時間を消費するだけになる。
    freedom = [ ];
  };
  # RAGの埋め込みに使うモデル。
  # アクセラレータ別にしない理由は`nixos/ollama/option.nix`のオプションの説明にある。
  #
  # モデルの選定はblue-promptのKnowledge 10011チャンクと20問での実測に基づく。
  # multilingual-e5-largeはtop3命中率0.70/MRR 0.605で、
  # sentence-transformersのfp32とGGUFのq8_0で精度は変わらない。
  # 量子化をq8_0にするのは、f16との精度差が無い一方で、
  # 帯域で頭打ちになる6コアのseminarではq8_0の方が速いため。
  # bge-m3などへの乗り換えの検討はblue-prompt#196で継続している。
  # ref https://github.com/ncaq/blue-prompt/issues/171
  embedding = [ "multilingual-e5-large:q8_0" ];
}
