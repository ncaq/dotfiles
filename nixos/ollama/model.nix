# Ollamaに読み込ませるモデルの定義。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  enableCuda = config.local.ollama.enableCuda;
  fetchHuggingFace = import ../../lib/fetch-hugging-face.nix { inherit pkgs; };
  # ハードウェアの限界の範囲で汎用的に使えそうな知能のモデル。
  generalModels =
    if enableCuda then
      [
        # bulletは32GiBのVRAMに収まる範囲で汎用品質を優先して27Bのdenseを使う。
        # mtpタグはMulti-Token Predictionのヘッドを含み、
        # GPUでは投機的デコーディングで生成速度が上がる。
        # bulletでの実測ではmtpの付かないq4_K_Mが81トークン/秒に対し、
        # mtp版は127トークン/秒で、
        # VRAMの増加は1.3GiB程度に留まる。
        # q8_0は品質では上だが30GiBを占めてcontextを32768より伸ばせず、
        # 実測でも53トークン/秒とq4_K_Mの半分以下しか出ない。
        # NVIDIAのBlackwell向けに見えるnvfp4やmxfp8のタグはApple MLXエンジン用で、
        # pullしようとするとmacOSを要求されるためこの環境では選べない。
        "qwen3.8:27b-mtp-q4_K_M"
      ]
    else
      [
        # CPUの推論はメモリ帯域で頭打ちになり、
        # 1トークンごとに読み出す重みの量がそのまま速度を決める。
        # 総パラメータではなくactive parameterが効くため、
        # 同じ品質帯ならdenseよりMoEの方が圧倒的に速い。
        # seminarでの実測では9Bのdenseが約10トークン/秒に対し、
        # このactive 3BのMoEは約19トークン/秒だった。
        # generalModelsをqwen3.8へ揃えられないのは、
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
  # 即答性を優先したモデル。
  flashModels =
    if enableCuda then
      [
        # GPUなら9Bのdenseでも体感は即答なので、
        # 速度のために品質を落とし過ぎない範囲で汎用モデルより一段小さいものを選ぶ。
        # 汎用モデルより世代が古いのは、
        # qwen3.6以降が27B以上しか公開されておらず、
        # この規模ではqwen3.5が最新だからである。
        # 9B級は27B級より量子化の劣化が効きやすいのでq8_0を選ぶ。
        # bulletでの実測ではq4_K_Mの201トークン/秒に対し143トークン/秒だが、
        # 短い応答なら1秒未満で返るので即答性は損なわれない。
        "qwen3.5:9b-q8_0"
      ]
    else
      [
        # active 1BのMoE。
        # generalModelsと同じくCPUではactive parameterの少なさがそのまま速度になる。
        # seminarでの実測では同じ質問への応答完了まで、
        # `qwen3.6:35b-a3b`が約18トークン/秒で46秒かかるのに対し、
        # このモデルは約45トークン/秒で7秒だった。
        # 同程度の規模でも`granite4.1:3b`のdenseは約24トークン/秒、
        # `qwen3.5:4b`のdenseは約16トークン/秒しか出ない。
        # bulletのflashModelsと違いq8_0を選ばないのは、
        # CPUでは重みの読み出し量がそのまま速度になるためで、
        # seminarでの実測では`lfm2.5:8b-a1b-q8_0`は約28トークン/秒まで落ちる。
        # 即答性を捨てるならgeneralModelsを使えば済む。
        "lfm2.5:8b"
      ];
  # 表現の自由度を優先したモデル。
  # CPUで推論するホストには置かない。
  # seminarでの実測では24Bのdenseは約4トークン/秒しか出ず、
  # 対話を待っていられる速度ではないため、
  # ディスクとロード時間を消費するだけになる。
  freedomModels = lib.optionalAttrs enableCuda {
    # Qwen3.8-27Bをheretic(ARA: Arbitrary-Rank Ablation)で拒否挙動だけ除去したもの。
    # 単一の拒否方向を引き算する従来のabliterationと違い重み行列を直接最適化するため、
    # 配布元の計測ではKL divergenceが基のQwen3.8-27Bに対して0.0085と小さく、
    # 拒否率は99/100から0-1/100まで落ちている。
    # 素の知能を保ったまま規制だけ外れるので、
    # 創作用に別途finetuneされたモデルとは性格が違い、
    # 汎用の受け答えの延長で自由度が欲しい場合に効く。
    # mtp版を選ぶのはgeneralModelsと同じ理由で、
    # MTPのドラフトヘッドを埋め込んだGGUFはGPUの投機的デコーディングで速度が上がる。
    # 量子化は他のfreedomModelsと同じくq4_k_mにする。
    # 配布元のREADMEは32GBのGPUにq6_kやq8_0を勧めているが、
    # あれは実効contextを24Kから64K程度と想定した表で、
    # bulletの`OLLAMA_CONTEXT_LENGTH`である131072では成立しない。
    # このcontextではKV cacheと計算バッファだけで10GiB以上要る。
    # bulletでの実測ではq4_k_mが100%GPUで80.3トークン/秒、
    # VRAMの空きも5.6GiB残るのに対し、
    # 本体が5.2GiB大きいq6_kは6%がCPUへ溢れて34.8トークン/秒まで落ちた。
    # 言語モデル本体だけではvisionが付かないので、
    # clipの投影器であるmmprojも一緒に渡す。
    # registryの`qwen3.8:27b-mtp-q4_K_M`がpullしただけでvisionを持つのは、
    # 同じ投影器をマニフェストの別レイヤーとして同梱しているからで、
    # Hugging Faceから本体のGGUFを1ファイル取るだけでは付いてこない。
    # 配布元は本体の量子化を変えた`-vision`付きのファイルも置いているが、
    # あれは画像の埋め込みを受ける層をq8_0で保護しただけの言語モデルで、
    # 使うにはどのみち投影器が要る上にmtp版が存在しない。
    # 投影器は`ggml-org/Qwen3.8-27B-GGUF`にある公式のものと同一で、
    # ARAは言語モデル側の層しか触っていないため素の投影器がそのまま噛み合う。
    # bulletでの実測でも`ollama show`の`Projector`はregistry版と同じ、
    # clipの460.73Mパラメータとして認識される。
    "qwen3.8-27b-heretic-rvn:q4_k_m" = [
      (fetchHuggingFace {
        owner = "0bserverx";
        repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
        rev = "2aff31a04896ab1f3716dde35f73d099ed0c08c5";
        file = "RVN-Q4_K_M-mtp.gguf";
        hash = "sha256-N5dNFvyF66qh6v/ZIr+jAtGm1YccapLtBh5Hj7hKX1c=";
      })
      (fetchHuggingFace {
        owner = "0bserverx";
        repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
        rev = "2aff31a04896ab1f3716dde35f73d099ed0c08c5";
        file = "mmproj-Qwen3.8-27B-Q8_0.gguf";
        hash = "sha256-LpaKavl8412JcYkLJXubftq/IK2RRQUB+lMWKhnuM+s=";
      })
    ];
    "mistralprism-24b:q4_k_m" = [
      (fetchHuggingFace {
        owner = "Aratako";
        repo = "MistralPrism-24B-GGUF";
        rev = "ef08191bef153caaa70e0720a8fcfa1cf11fb10b";
        file = "MistralPrism-24B-Q4_K_M.gguf";
        hash = "sha256-Tm9H9IXyhqSnPhzA0KZhwU8fNYWyK1XcdRKFGfB0Fdw=";
      })
    ];
    "ms3.2-24b-magnum-diamond:q4_k_m" = [
      (fetchHuggingFace {
        owner = "Doctor-Shotgun";
        repo = "MS3.2-24B-Magnum-Diamond-GGUF";
        rev = "7422a3599b749c9efa003c53f3165adc71e1f2aa";
        file = "MS3.2-24B-Magnum-Diamond-Q4_K_M.gguf";
        hash = "sha256-MLwAq6iPY52EsZwZ2bxVaHHQBGbDJuyc9U7F+Y6PVsQ=";
      })
    ];
  };
in
{
  local.ollama = {
    inherit generalModels flashModels freedomModels;
  };
}
