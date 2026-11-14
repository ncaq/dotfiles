# Ollamaに読み込ませるモデルの定義。
{
  lib,
  pkgs,
  pkgs-unstable,
  config,
  inputs,
  ...
}:
let
  enableCuda = config.local.ollama.enableCuda;
  fetchHuggingFace = import ../../lib/fetch-hugging-face.nix { inherit pkgs; };
  # NextN層を持つQwen3.8を量子化できるのはunstableのllama.cppだけなのでunstableを渡す。
  quantizeGgufWithNextn = import ../../lib/quantize-gguf-with-nextn.nix { pkgs = pkgs-unstable; };
  # CLIと同じstoreのパスを使うため、取得の定義は`lib/`で共有している。
  plamoTranslateModel = import ../../lib/plamo-translate-model.nix { inherit pkgs; };
  patchGgufChatTemplate = import ../../lib/patch-gguf-chat-template.nix {
    inherit pkgs;
    inherit (inputs) himari-src;
  };
  # registryのQwen3.8が同梱しているパラメータ。
  # GGUFから自前で組み立てるとparamsレイヤーが付いてこないので明示する。
  # `draft_num_predict`が特に重要で、
  # MTPのドラフトヘッドを埋め込んだGGUFでもこれを指定しないと投機的デコーディングが動かない。
  # bulletでの実測では、
  # 指定していなかった`qwen3.8-27b-heretic-rvn:q4_k_m`が80.4トークン/秒だったのに対し、
  # 同じGGUFにこれを足すだけで141.4トークン/秒まで上がった。
  #
  # 値の4は実測で最も速かったものである。
  # `qwen3.8-27b-mtp:q6_k`でbulletで同じ問いを2回ずつ測ると、
  # 2が120.8と124.3、3が135.9と136.8、
  # 4が137.6と137.9、5が134.6と135.0トークン/秒だった。
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
  # Ollama registryのblobを取得する。
  # blobはダイジェストで指定され中身がそのsha256なので、
  # ダイジェストをそのままハッシュに使えてタグの差し替えに影響されない。
  fetchOllamaBlob =
    {
      name,
      model,
      digest,
    }:
    pkgs.fetchurl {
      inherit name;
      url = "https://registry.ollama.ai/v2/library/${model}/blobs/sha256:${digest}";
      hash = "sha256:${digest}";
    };
  # アクセラレータごとに、役割から実際のモデル名を引く表。
  # home-managerの設定もこれを読むため、実体は`lib/`に置いている。
  # 理由はそのファイルの先頭に書いてある。
  modelNames = import ../../lib/ollama-model-names.nix;
  # PLaMo 3 Translateの配布元が推奨する生成の設定。
  #
  # 学習時の最大長は入力と出力の合計で32768トークンなので、
  # contextをそれ以上伸ばしても長文の翻訳は保証されない。
  # bulletの既定の長さのままだとKVキャッシュがVRAMを余計に占めるので、
  # 学習時の長さに揃える。
  # 長さを超えた分の品質が保証されずKVキャッシュがメモリを余計に使うのは、
  # CPUで推論するホストのメインメモリでも同じなので、
  # 8Bにも同じ設定を使う。
  #
  # 翻訳文の終わりにモデルは`<|plamo:tag|>`か`<|plamo:bos|>`を出す。
  # 後者はGGUFのeosなので、停止文字列として足すのは前者だけでよい。
  #
  # チャットテンプレートはGGUFに埋め込まれたJinjaをOllamaがllama-serverへ渡して使う。
  # Ollamaは`chat_template_kwargs`を受け取れないので、
  # 訳す言語などは先頭のsystemメッセージに`[plamo-translate]`の形式で書く。
  # 省略すると日本語と英語の間で自動的に向きを切り替える。
  #
  # 配布元のGGUFには`yarn_truncate=false`の設定が入っているが、
  # 今のllama.cppはまだこれを解釈しないため、
  # 長文では配布元の想定と少しずれた訳になる場合がある。
  # 公式のCLIはllama-serverへyarnの引数を直接渡して回避しているが、
  # Ollamaにはその引数を渡す手段が無い。
  # 長さはOpenCodeの設定も必要とするので`lib/ollama-context.nix`が持っている。
  plamoTranslateParameters = {
    num_ctx = (import ../../lib/ollama-context.nix).translateLength;
    stop = "<|plamo:tag|>";
    temperature = 0;
  };
  ggufModels =
    lib.optionalAttrs enableCuda {
      # registryに無い量子化でQwen3.8-27Bを使うための自前ビルド。
      # MTPのドラフトヘッドはQwen3.8の公式の重みに元から入っており、
      # 対応したllama.cppで変換すれば`qwen35.nextn_predict_layers=1`として、
      # 本体と同じGGUFの中に15テンソル約451MBで残る。
      #
      # 公式の重みからggml-orgが変換したBF16を取り、自分でQ6_Kへ量子化する。
      # ggml-orgはドラフトヘッドを`mtp-*.gguf`として本体から切り離して配っているので、
      # 量子化の前に本体へまとめ直す。
      # まとめる方法とその理由は`lib/quantize-gguf-with-nextn.nix`にある。
      #
      # ggml-orgの変換のチャットテンプレートはassistantの発話を`{% generation %}`で囲んでいる。
      # assistantの発話を含む会話をOllamaで生成できることを確かめた。
      #
      # 登録した結果が公式のQwen3.8-27Bと噛み合うことを確認した。
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
      # unslothのQ6_Kをそのまま使わないのは、
      # ggml-orgと同じくMTPのドラフトヘッドを`MTP/mtp-*.gguf`として別ファイルに切り出しているからである。
      # 本体と一緒に`FROM`へ並べると`ollama create`は取り込みこそするものの、
      # マニフェストに`model`のレイヤーが2つ並ぶ形になり、
      # ollamaは最後の`model`レイヤーを本体だと解釈する。
      # bulletではドラフトヘッドが後ろに来て、
      # 1.28GiBのドラフトを本体としてロードしたllama-serverがsegmentation faultで落ちた。
      # レイヤーの並びは`FROM`の順番では制御できないため、
      # 別ファイルのドラフトヘッドは`FROM`では使えない。
      # 今のOllamaにはドラフトを指定する`DRAFT`があるが、
      # NextN層だけのGGUFを渡せるかは確かめていない。
      #
      # visionはregistry版がマニフェストの別レイヤーとして同梱しているだけなので、
      # 本体のGGUFを取るだけでは付いてこず、clipの投影器を自分で足す必要がある。
      # 投影器はunslothのF16を使う。
      # registry版の投影器も888MiBでF16相当なので、それに揃える。
      #
      # チャットテンプレートはそのままではコーディングエージェントからの入力を弾くので、
      # `qwen3.8-chat-template.patch`を当てて緩和したものを登録する。
      # 弾かれる入力と緩和の内容はそのパッチファイルの先頭に書いてある。
      "qwen3.8-27b-mtp:q6_k" = {
        sources = [
          (patchGgufChatTemplate {
            gguf = quantizeGgufWithNextn {
              name = "Qwen3.8-27B-MTP-Q6_K.gguf";
              model = fetchHuggingFace {
                owner = "ggml-org";
                repo = "Qwen3.8-27B-GGUF";
                rev = "8ccda149192dec5f41450a402e66889e5fd25a24";
                file = "Qwen3.8-27B-BF16.gguf";
                hash = "sha256-7hHoaU5cXP+griGJVwbJc2A1DkBTKXkwi3VtIKmnF70=";
              };
              draft = fetchHuggingFace {
                owner = "ggml-org";
                repo = "Qwen3.8-27B-GGUF";
                rev = "8ccda149192dec5f41450a402e66889e5fd25a24";
                file = "mtp-Qwen3.8-27B-BF16.gguf";
                hash = "sha256-n8QonqUMFvNWcyFBWW8zgOdHcjy5EikaoLj+z9j5Jzw=";
              };
              type = "Q6_K";
              hash = "sha256-T6KMlLIqOin7XqDldVnLh49fg3bdSwLNqm9hwme0mSg=";
            };
            patch = ./qwen3.8-chat-template.patch;
            hash = "sha256-3UfAApLmAbkXsNKXJfV1YhPDRl0VmRTjWbwEiDMzl68=";
          })
          (fetchHuggingFace {
            owner = "unsloth";
            repo = "Qwen3.8-27B-GGUF";
            rev = "43f522df59109a037f64f1e29ab1eff5c00e8e1e";
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
      #
      # チャットテンプレートには汎用モデルと同じ`qwen3.8-chat-template.patch`を当てる。
      # ARAは重みしか触っておらずテンプレートは素のQwen3.8のままだからである。
      # 汎用モデルのggml-orgの変換はassistantの発話を`{% generation %}`で囲む点だけが異なるが、
      # パッチが触る箇所はどちらも同じ形をしている。
      # 今の呼び出し側であるOpen WebUIが弾かれる形を送っているわけではないが、
      # reasoning effortを明示する経路があれば同じ500に当たる。
      # 片方だけ緩和されている状態は、
      # 役割を入れ替えた時に理由の分からない失敗として現れる。
      "qwen3.8-27b-heretic-rvn:q6_k" = {
        sources = [
          (patchGgufChatTemplate {
            gguf = fetchHuggingFace {
              owner = "0bserverx";
              repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
              rev = "ab8d7bd81d03117501e4da60cccdff4c80f0eea0";
              file = "RVN-Q6_K-multilingual-mtp.gguf";
              hash = "sha256-E0TQdCXXPw0bjzYhORDq6P7CEGGxqQg1kn6EhSOPk6Q=";
            };
            patch = ./qwen3.8-chat-template.patch;
            hash = "sha256-hzzpKJupdhn7aQhIWzP8t/lLkfQ5YUSFojOHPORu5ro=";
          })
          (fetchHuggingFace {
            owner = "0bserverx";
            repo = "Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF";
            rev = "ab8d7bd81d03117501e4da60cccdff4c80f0eea0";
            file = "mmproj-Qwen3.8-27B-Q8_0.gguf";
            hash = "sha256-LpaKavl8412JcYkLJXubftq/IK2RRQUB+lMWKhnuM+s=";
          })
        ];
        parameters = qwenParameters;
      };
      # registryの`gemma4:31b`と同じものを、
      # タグではなくblobのダイジェストで固定して組み立てる。
      # タグは上流で差し替わり得て、
      # VRAMの空きが少ないので中身が変わると溢れるかもしれないためである。
      # 本体と投影器とMTPのドラフトのblob、
      # およびTEMPLATEとRENDERERとPARSERとparamsは、
      # 2026-11-13時点のタグのマニフェストと`ollama show --modelfile`の内容に揃えてある。
      "gemma4-31b-mtp:q4_k_m" = {
        sources = [
          (fetchOllamaBlob {
            name = "gemma4-31b-q4_k_m.gguf";
            model = "gemma4";
            digest = "cd20f2b3f2e30239023189c04e65754b0cc7c38959665ac727461ee470df16cf";
          })
          (fetchOllamaBlob {
            name = "gemma4-31b-projector.gguf";
            model = "gemma4";
            digest = "6357a8a2d521e7b3b67d5afd3a6f5094b2712736b5bd6e1c9f17f8e4e6fae9b0";
          })
        ];
        draft = fetchOllamaBlob {
          name = "gemma4-31b-draft.gguf";
          model = "gemma4";
          digest = "9ec411cf75f3ab210708dad5adb53d98a151f2c72f0659da97892b8a0a14e3e3";
        };
        template = "{{ .Prompt }}";
        renderer = "gemma4";
        parser = "gemma4";
        parameters = {
          draft_num_predict = 3;
          temperature = 1;
          top_k = 64;
          top_p = 0.95;
        };
      };
      # 翻訳特化のPLaMo 3 Translate。
      "plamo-3-translate-31b:q4_k_m" = {
        sources = [ plamoTranslateModel."31b-q4_k_m" ];
        parameters = plamoTranslateParameters;
      };
    }
    // lib.optionalAttrs (!enableCuda) {
      # CPUで推論するホスト向けのPLaMo 3 Translate。
      "plamo-3-translate-8b:q4_k_m" = {
        sources = [ plamoTranslateModel."8b-q4_k_m" ];
        parameters = plamoTranslateParameters;
      };
    }
    // {
      # RAGの埋め込み用モデル。CUDAの有無に関係なく全てのOllamaホストへ登録する。
      # Open WebUIからの埋め込み要求はCaddyのフェイルオーバーがホストを選ぶため、
      # どちらのホストでも同じモデルが引ける必要がある。
      #
      # registryのpullではなくGGUFから組むのは`num_gpu 0`を焼き込むためである。
      # bulletは27Bのチャットモデルを載せると空きVRAMが約2.5GiBしかなく、
      # 埋め込みモデルを同居させるとデスクトップ用途の描画が押し出されるので、
      # 埋め込みはCPUに縛る。CPUでもGGUFはtorchのfp32より速い。
      #
      # このGGUFが正しい変換であることは、
      # 精度の実測に使ったregistryのjeffh/intfloat-multilingual-e5-large:q8_0と、
      # 同じ文書の埋め込みのコサイン一致度が平均・最小とも1.000000であることで確認した。
      # ref https://github.com/ncaq/blue-prompt/issues/171
      "multilingual-e5-large:q8_0" = {
        sources = [
          (fetchHuggingFace {
            owner = "soichisumi";
            repo = "multilingual-e5-large-Q8_0-GGUF";
            rev = "aefacc2937c5710d215b9d20e1a02f0df0f79555";
            file = "multilingual-e5-large-q8_0.gguf";
            hash = "sha256-b8CGpD+p+adm7mZDEuzy8wH/JMifhmxkk25bTFCZs74=";
          })
        ];
        parameters = {
          num_gpu = 0;
        };
      };
    };
  # 全てのアクセラレータの全ての役割に現れるモデル名。
  declaredModels =
    lib.concatMap (models: models.general ++ models.freedom ++ models.translate) [
      modelNames.cuda
      modelNames.cpu
    ]
    ++ modelNames.embedding;
  # 役割のリストに載っていない`ggufModels`の定義。
  orphanGgufModels = lib.subtractLists declaredModels (lib.attrNames ggufModels);
in
{
  local.ollama = {
    models = modelNames;
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
