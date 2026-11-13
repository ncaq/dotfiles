/**
  アクセラレータごとに、役割から実際のモデル名を引く表。

  型: { cuda = { general, freedom, translate }; cpu = { general, freedom, translate }; embedding; }

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
    # 対話を待っていられる速度を出すため、
    # どのモデルもKVキャッシュまで含めて32GiBのVRAMに乗り切るものを選ぶ。
    # 少しでもCPUへ溢れると速度が大きく落ちるためである。
    # bulletでQwen3.8-27Bの量子化違いを同じ条件
    # (KVキャッシュq8_0, context 131072, 1024トークンの生成を2回)で測ると以下の通り。
    # - q4_K_M: 23.1GiBで全層がGPUに載り、114.6と114.4トークン/秒
    # - q6_k: 28.0GiBで全層がGPUに載り、98.5と104.6トークン/秒
    # - q8_0: ギリギリ載らず24%がCPUへ溢れ、13.3と12.2トークン/秒
    # 載る範囲で重みを大きくしても速度の差は1割強に収まるが、
    # 一段上げて溢れた途端に速度は1/8まで落ちる。
    # 互いに同時にはVRAMへ載らないが、
    # VRAMが足りなければOllamaがアイドル中のモデルを降ろすので入れ替わりで動く。
    general = [
      # Googleの31Bのdense。visionに対応する。
      # registryの既定タグ`gemma4:31b`をblobのダイジェストで固定して組み立てたもの。
      # Q4_K_Mの本体にMTPのドラフトと投影器が付く。
      # bulletでの実測(KVキャッシュq8_0, context 131072)は以下の通り。
      # - llama-server: 28.1GiBで全層がGPUに載る
      # - VRAMの空き: 1.6GiB
      # - 生成速度: 同じ条件で2回測って123.3と132.4トークン/秒
      # 一段上のq8_0は本体だけで30.39GiBあり、KVキャッシュを載せる余地が無い。
      "gemma4-31b-mtp:q4_k_m"
      # Alibabaの27Bのdense。visionに対応する。
      # 量子化は上の実測で全層がGPUに載る中で最も重いq6_kにする。
      # registryのmtp付きタグはq4_K_Mとq8_0とbf16しか無いので、
      # Hugging FaceのGGUFから自前で組む。
      # q6_kは量子化としては事実上無損失の領域なので、
      # これ以上重みに割いても品質はほとんど変わらない。
      # 一段上のq8_0は本体だけで27GiBあり、
      # contextを32768まで削ってKVを3.2GiB浮かせても載らない。
      "qwen3.8-27b-mtp:q6_k"
    ];
    freedom = [ "qwen3.8-27b-heretic-rvn:q6_k" ];
    # 配布元の評価ではQ4_K_MとBF16の翻訳精度の差は誤差の範囲に収まる。
    # 19.5GBあるので汎用モデルとは同時にVRAMへ載らないが、
    # 汎用モデル同士と同じく入れ替わりで動く。
    translate = [ "plamo-3-translate-31b:q4_k_m" ];
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
    # 31Bのdenseは`freedom`で外した24Bのdenseと同様にCPUでは待っていられる速度が出ないので8Bにする。
    # 配布元の評価では8Bと31Bの翻訳精度の差は小さい。
    translate = [ "plamo-3-translate-8b:q4_k_m" ];
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
