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
  patchGgufChatTemplate = import ../../lib/patch-gguf-chat-template.nix { inherit pkgs; };
  # registryのQwen3.8が同梱しているパラメータ。
  # GGUFから自前で組み立てるとparamsレイヤーが付いてこないので明示する。
  # `draft_num_predict`が特に重要で、
  # MTPのドラフトヘッドを埋め込んだGGUFでもこれを指定しないと投機的デコーディングが動かない。
  # bulletでの実測では、
  # 指定していなかった`qwen3.8-27b-heretic-rvn:q4_k_m`が80.4トークン/秒だったのに対し、
  # 同じGGUFにこれを足すだけで141.4トークン/秒まで上がった。
  #
  # 値の4は配布元の推奨より長い。
  # JackrongのREADMEは`--spec-draft-n-max 2`を勧めているが、
  # bulletで同じ問いを2回ずつ測ると2が127.0と127.2、
  # 4が133.6と134.2トークン/秒で4の方が速い。
  # 投機的デコーディングはドラフトを伸ばすほど末尾の受理率が下がるものの、
  # 実測の位置ごとの受理率は4本目でも0.369あり、
  # 外した分の検証コストを補って余る。
  #
  # 残りはQwen3.8公式のThinking Mode向けの推奨サンプリングで、
  # Ollamaの既定値(temperature 0.8, top_k 40, top_p 0.9, repeat_penalty 1.1)とは異なる。
  # 公式はthinkingを切る場合にtemperature 0.7とtop_p 0.80とpresence_penalty 1.5を勧めているので、
  # 思考を止めて使いたい呼び出し側は自分で上書きする必要がある。
  qwenParameters = {
    draft_num_predict = 4;
    min_p = 0;
    presence_penalty = 0;
    repeat_penalty = 1;
    temperature = 1;
    top_k = 20;
    top_p = 0.95;
  };
  cudaModels = {
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
  cpuModels = {
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
  ggufModels = lib.optionalAttrs enableCuda {
    # registryに無い量子化でQwen3.8-27Bを使うための自前ビルド。
    # MTPのドラフトヘッドはQwen3.8の公式の重みに元から入っており、
    # 対応したllama.cppで変換すれば`qwen35.nextn_predict_layers=1`として、
    # 本体と同じGGUFの中に15テンソル約451MBで残る。
    # Jackrongのリポジトリはそれを捨てずに量子化したもので、
    # 素のQwen3.8に対する改変は入っていない。
    #
    # 供給元がOllama公式のregistryから個人のリポジトリへ移るため、
    # 登録した結果が公式のQwen3.8-27Bと噛み合うことを一度確認した。
    # `ollama show`が返す値は`Qwen/Qwen3.8-27B`の`config.json`と以下の通り一致する。
    #
    # - context lengthの262144が`max_position_embeddings`
    # - embedding lengthの5120が`text_config.hidden_size`
    # - 投影器のembedding lengthの1152が`vision_config.hidden_size`
    # - 投影器のdimensionsの5120が`vision_config.out_hidden_size`
    #
    # capabilitiesにもtoolsとthinkingとvisionが揃い、
    # 投影器はregistry版と同じclipの460.73Mパラメータとして認識される。
    # `rev`と`hash`で固定しているので、
    # 配布元が後から差し替えた場合はビルドが壊れて気付ける。
    #
    # unslothも同じ量子化を配っているが、
    # あちらはMTPのドラフトヘッドを`MTP/mtp-*.gguf`として別ファイルに切り出している。
    # 本体と一緒に`FROM`へ並べると`ollama create`は取り込みこそするものの、
    # マニフェストに`model`のレイヤーが2つ並ぶ形になり、
    # ollamaは最後の`model`レイヤーを本体だと解釈する。
    # bulletではドラフトヘッドが後ろに来て、
    # 1.28GiBのドラフトを本体としてロードしたllama-serverがsegmentation faultで落ちた。
    # レイヤーの並びは`FROM`の順番では制御できず、
    # Modelfileにドラフトを指定する構文も無いため、
    # 別ファイルのドラフトヘッドは使えない。
    #
    # visionはregistry版がマニフェストの別レイヤーとして同梱しているだけなので、
    # 本体のGGUFを取るだけでは付いてこず、clipの投影器を自分で足す必要がある。
    # 投影器はunslothのF16を使う。
    # registry版の投影器も888MiBでF16相当であり、
    # Jackrongが置いているF32は1.72GiBと倍を占める割に得るものが無い。
    #
    # チャットテンプレートはそのままではコーディングエージェントからの入力を弾くので、
    # `qwen3.8-chat-template.patch`を当てて緩和したものを登録する。
    # 弾かれる入力と緩和の内容はそのパッチファイルの先頭に書いてある。
    "qwen3.8-27b-mtp:q6_k" = {
      sources = [
        (patchGgufChatTemplate {
          gguf = fetchHuggingFace {
            owner = "Jackrong";
            repo = "Qwen3.8-27B-MTP-GGUF";
            rev = "422451108d80df4a55ebd66c3416af42a0ce0b0c";
            file = "Qwen3.8-27B-MTP-Q6_K.gguf";
            hash = "sha256-0PqUrycPPeQmll8fn29hQKrp9arZuIu0ZkUkknSNUm4=";
          };
          patch = ./qwen3.8-chat-template.patch;
        })
        (fetchHuggingFace {
          owner = "unsloth";
          repo = "Qwen3.8-27B-GGUF";
          rev = "4ca720788d1e01f1bff70c033e0d0028fd02e502";
          file = "mmproj-F16.gguf";
          hash = "sha256-y7hBqe4GNrLsFy9buN8uqN/rAekP58YSZYHWYqC05D4=";
        })
      ];
      parameters = qwenParameters;
    };
    # Qwen3.8-27Bをheretic(ARA: Arbitrary-Rank Ablation)で拒否挙動だけ除去したもの。
    # 単一の拒否方向を引き算する従来のabliterationと違い重み行列を直接最適化するため、
    # 配布元の計測ではKL divergenceが基のQwen3.8-27Bに対して0.0085と小さく、
    # 拒否率は99/100から0-1/100まで落ちている。
    # 素の知能を保ったまま規制だけ外れるので、
    # 創作用に別途finetuneされたモデルとは性格が違い、
    # 汎用の受け答えの延長で自由度が欲しい場合に効く。
    # mtp版を選ぶのは汎用モデルと同じ理由で、
    # MTPのドラフトヘッドを埋め込んだGGUFはGPUの投機的デコーディングで速度が上がる。
    # `-multilingual`は配布元が新規のダウンロードに推奨している校正の系統で、
    # importance matrixが20以上の言語とコードと推論とツール利用の構造を含む。
    # 英語だけに低ビットの精度予算を寄せないので日本語で使うならこちらになる。
    # 量子化はq6_kまで上げる。
    # 配布元のREADMEは24GBのGPUではq6_kを「too tight」としているが、
    # あれは32GBのGPUを前提にしていない表である。
    # bulletでの実測(KVキャッシュq8_0, context 131072)では、
    # q6_kが28.6GiBで100%GPUに載って109.8トークン/秒、
    # VRAMの空きも2.7GiB残る。
    # 一段上のq8_0は本体だけで26.63GiBあり、
    # このcontextでは10GiB近いKVキャッシュと計算バッファを載せる余地が無い。
    # revを2aff31aから進めたのは配布元がテンプレートを修復したためで、
    # 古いGGUFはOllamaに`does not support thinking`と拒否されて、
    # Qwen3.8の思考を使えていなかった。
    # 言語モデル本体だけではvisionが付かないので、
    # clipの投影器であるmmprojも一緒に渡す。
    # 投影器は`ggml-org/Qwen3.8-27B-GGUF`にある公式のものと同一で、
    # ARAは言語モデル側の層しか触っていないため素の投影器がそのまま噛み合う。
    "qwen3.8-27b-heretic-rvn:q6_k" = {
      sources = [
        (fetchHuggingFace {
          owner = "0bserverx";
          repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
          rev = "20b94f0613b632b4848bbe3b1e05d9ee0c2b1608";
          file = "RVN-Q6_K-multilingual-mtp.gguf";
          hash = "sha256-E0TQdCXXPw0bjzYhORDq6P7CEGGxqQg1kn6EhSOPk6Q=";
        })
        (fetchHuggingFace {
          owner = "0bserverx";
          repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
          rev = "20b94f0613b632b4848bbe3b1e05d9ee0c2b1608";
          file = "mmproj-Qwen3.8-27B-Q8_0.gguf";
          hash = "sha256-LpaKavl8412JcYkLJXubftq/IK2RRQUB+lMWKhnuM+s=";
        })
      ];
      parameters = qwenParameters;
    };
    # Mistral Small系は配布元の推奨がQwenと大きく違うので個別に書く。
    # 配布元のREADMEがollamaとvLLMの実行例で使っている値をそのまま採る。
    # 学習元のMistral-Small-3.1が低いtemperatureを勧めているためで、
    # 配布元自身は「そうかもしれないが詳しくは未検証」と断っている。
    # 創作用途には低すぎると感じたら上げて構わない。
    "mistralprism-24b:q4_k_m" = {
      sources = [
        (fetchHuggingFace {
          owner = "Aratako";
          repo = "MistralPrism-24B-GGUF";
          rev = "ef08191bef153caaa70e0720a8fcfa1cf11fb10b";
          file = "MistralPrism-24B-Q4_K_M.gguf";
          hash = "sha256-Tm9H9IXyhqSnPhzA0KZhwU8fNYWyK1XcdRKFGfB0Fdw=";
        })
      ];
      parameters = {
        min_p = 0.05;
        temperature = 0.15;
        top_k = 40;
        top_p = 0.9;
      };
    };
    # 配布元は`temperature = 1.0`と`min_p = 0.1`から始めることを勧めている。
    # 他は好みで動かせという書き方なので、この2つだけ指定する。
    "ms3.2-24b-magnum-diamond:q4_k_m" = {
      sources = [
        (fetchHuggingFace {
          owner = "Doctor-Shotgun";
          repo = "MS3.2-24B-Magnum-Diamond-GGUF";
          rev = "7422a3599b749c9efa003c53f3165adc71e1f2aa";
          file = "MS3.2-24B-Magnum-Diamond-Q4_K_M.gguf";
          hash = "sha256-MLwAq6iPY52EsZwZ2bxVaHHQBGbDJuyc9U7F+Y6PVsQ=";
        })
      ];
      parameters = {
        min_p = 0.1;
        temperature = 1.0;
      };
    };
  };
  # 全てのアクセラレータの全ての役割に現れるモデル名。
  declaredModels = lib.concatMap (models: models.general ++ models.freedom) [
    cudaModels
    cpuModels
  ];
  # 役割のリストに載っていない`ggufModels`の定義。
  orphanGgufModels = lib.subtractLists declaredModels (lib.attrNames ggufModels);
in
{
  local.ollama = {
    models = {
      cuda = cudaModels;
      cpu = cpuModels;
    };
    inherit ggufModels;
  };

  # 役割のリストと`ggufModels`のキーは同じ文字列を二重に書くことになる。
  # 型はどちらも文字列としか言わないので、
  # 片方の量子化タグだけを書き換えても評価は成功してしまう。
  # その場合`loadModels`の引き算が噛み合わず、
  # registryに無い名前をpullしようとして失敗するか、
  # 組み立てたモデルを誰も参照しないまま置くかのどちらかになり、
  # 実機へ適用するまで気付けない。
  assertions = [
    {
      assertion = orphanGgufModels == [ ];
      message = ''
        local.ollama.ggufModelsのキーはいずれかの役割のリストに載っている必要があります。
        載っていないキー: ${lib.concatStringsSep ", " orphanGgufModels}
      '';
    }
  ];
}
