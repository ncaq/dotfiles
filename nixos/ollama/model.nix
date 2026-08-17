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
    "mistralprism-24b:q4_k_m" = fetchHuggingFace {
      owner = "Aratako";
      repo = "MistralPrism-24B-GGUF";
      rev = "ef08191bef153caaa70e0720a8fcfa1cf11fb10b";
      file = "MistralPrism-24B-Q4_K_M.gguf";
      hash = "sha256-Tm9H9IXyhqSnPhzA0KZhwU8fNYWyK1XcdRKFGfB0Fdw=";
    };
    "qwen3-30b-a3b-erp-v0.1:q4_k_m" = fetchHuggingFace {
      owner = "Aratako";
      repo = "Qwen3-30B-A3B-ERP-v0.1-GGUF";
      rev = "78221ae35684a78dec965c1041c0bf10e0ff16d9";
      file = "Qwen3-30B-A3B-ERP-v0.1-Q4_K_M.gguf";
      hash = "sha256-Tzvnhjb74SOYzBIGvG4XqcYUelcaDLb5dTH0UrGpSAM=";
    };
    "ms3.2-24b-magnum-diamond:q4_k_m" = fetchHuggingFace {
      owner = "Doctor-Shotgun";
      repo = "MS3.2-24B-Magnum-Diamond-GGUF";
      rev = "7422a3599b749c9efa003c53f3165adc71e1f2aa";
      file = "MS3.2-24B-Magnum-Diamond-Q4_K_M.gguf";
      hash = "sha256-MLwAq6iPY52EsZwZ2bxVaHHQBGbDJuyc9U7F+Y6PVsQ=";
    };
  };
in
{
  local.ollama = {
    inherit generalModels flashModels freedomModels;
  };
}
