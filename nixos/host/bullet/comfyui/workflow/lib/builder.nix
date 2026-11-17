# ComfyUIのワークフローJSON(UI形式)をNix式で組み立てるための共有部品。
#
# UI形式のノードの`widgets_values`は配列で、
# 並び順はノード定義のINPUT_TYPESのウィジェット順に一致させる必要がある。
{ lib }:
let
  self =
    let
      checkpoint = "waiIllustriousSDXL_v170.safetensors";
      positivePrompt = "best quality, amazing quality, masterpiece, 1girl";
      negativePrompt = "bad quality, worst quality, worst detail, sketch, censored, watermark, signature";
      # Illustrious系モデルの定番サンプリング設定。
      samplerName = "euler_ancestral";
      schedulerName = "normal";
      # SDXLのポートレートバケット解像度をデフォルトにする。
      defaultWidth = 832;
      defaultHeight = 1216;
      # Qwen-Image VAEの8倍圧縮とAnimaのspatial patch size 2を掛けた画像寸法の整列単位。
      animaSizeMultiple = 16;
      # denoise 1のtxt2imgで使うステップ数。
      # SDXL(Illustrious系)とAnimaでそれぞれの推奨値が違う。
      baseSteps = 28;
      animaBaseSteps = 30;
      # Qwen-Image-2.1の編集で参照画像と出力を揃える総画素の平方根。
      # 各画像はアスペクト比を保ったまま約2048*2048画素の32の倍数へ揃えられる。
      # 公式の解像度プリセットは全て約4MPのネイティブ2Kなので、
      # それに合わせるのがモデルの得意な範囲になる。
      # 公式テンプレートの0は元の寸法を32の倍数へ丸めるだけで、
      # 写真のような大きな画像がそのまま入って重くなる。
      #
      # 公式のdiffusersパイプラインも参照画像は全て1つの`output_resolution`へ揃え、
      # 出力の寸法だけを別に決める。
      # エンコードと書き換えの両方へ同じ値を渡して、
      # 1枚目に従う時に出力と1枚目の寸法が一致するようにする。
      qwenImageEditResolution = 2048;
      # denoiseを下げた再サンプリングで使うステップ数を求める。
      #
      # ComfyUIのKSamplerはdenoiseを下げても`steps`の回数だけサンプリングする。
      # `int(steps / denoise)`ステップ分のsigma列を作ってその末尾`steps`個を使う実装で、
      # A1111のように実行回数が`steps * denoise`へ減ることはない。
      # そのためdenoiseを下げただけのつもりで素の生成より重い設定になりやすい。
      # sigmaの刻み密度を素の生成へ揃えるには`基準のsteps * denoise`にすれば良い。
      #
      # 四捨五入ではなく切り捨てるのは、
      # 刻み密度を素の生成以下に保って実行コストの上限も同時に押さえるためと、
      # 積がちょうど0.5になる組み合わせで結果をdoubleの転び方に委ねないためである。
      # `30 * 0.35`のように実際に使う値がこの境界に乗っていて、
      # 四捨五入では1ステップの差が浮動小数点の表現誤差次第になる。
      stepsForDenoise = base: denoise: lib.max 1 (builtins.floor (base * denoise));
      # 強さを実行時に変えるワークフロー向けに、
      # 同じサンプリングをKSamplerAdvancedの`start_at_step`として表した値を求める。
      #
      # KSamplerAdvancedは`steps`本のsigma列の`start_at_step`番目から流すため、
      # 実行回数が`steps - start_at_step`になり、
      # 刻み密度は常に素の生成と同じまま強さだけが変わる。
      # denoiseと違って強さとステップ数が構造的に連動するので、
      # 実行時に強さを変えてもステップ数の付け替えが要らない。
      #
      # denoiseが1以上だと0以下を返して全ステップ実行に戻ってしまうため、
      # 呼び出し側の想定外の値を表明で弾く。
      startStepForDenoise =
        base: denoise:
        assert lib.assertMsg (denoise < 1) "startStepForDenoiseはdenoiseが1未満の時にだけ意味を持ちます";
        base - (stepsForDenoise base denoise);
      # seedウィジェットは値の直後に実行後の挙動(randomizeなど)が並ぶ。
      seedWidgets = [
        0
        "randomize"
      ];

      # 出力をワークフローごとのサブディレクトリへ分けて、
      # ファイル名を連番だけでなく生成日時にするfilename_prefixを組み立てる。
      # %year%などの置換はサーバ側のfolder_paths.get_save_image_pathが行うため、
      # フロントエンドの%date:...%と違い自作ノードを含む全ての保存ノードで機能する。
      # 第1引数はワークフロー名で、サブディレクトリ名とファイル名の両方に使われる。
      # 第2引数はファイル名だけに足すサフィックスで、
      # 同じワークフローが複数の保存ノードを持つ時に役割を区別する。
      # サブディレクトリはワークフロー単位のままなので階層は増えない。
      mkFilenamePrefixWith =
        name: suffix: "${name}/${name}${suffix}-%year%-%month%-%day%-%hour%-%minute%-%second%";
      mkFilenamePrefix = name: mkFilenamePrefixWith name "";

      mkNode =
        {
          id,
          type,
          pos,
          size,
          # ノードの実行順。
          # ノードごとに一意で、かつリンクの依存に沿って増える値を振る。
          # `lib/order.nix`の検証がこの規約を機械的に確かめる。
          order,
          inputs ? [ ],
          outputs ? [ ],
          widgets ? null,
          # ノードの表示名。役割が分かる名前を付ける時に指定する。
          # 未指定ならComfyUIがノード型のデフォルト表示名を使う。
          title ? null,
        }:
        {
          inherit
            id
            type
            pos
            size
            order
            inputs
            outputs
            ;
          flags = { };
          mode = 0;
          properties = {
            "Node name for S&R" = type;
          };
        }
        // lib.optionalAttrs (widgets != null) { widgets_values = widgets; }
        // lib.optionalAttrs (title != null) { inherit title; };
      mkInput = name: type: link: { inherit name type link; };
      mkOutput = name: type: links: { inherit name type links; };
      mkAppInput = nodeId: widgetName: [
        nodeId
        widgetName
      ];
      mkAppInputWith = nodeId: widgetName: config: [
        nodeId
        widgetName
        config
      ];
      # LoRA Managerの`Lora Loader (LoraManager)`ノード。
      # LoRAが未指定ならMODELとCLIPをそのまま素通しするので、
      # 常に配線したままで良い。
      # LoRA Managerの管理画面のSend to Workflowがこのノードへ流し込む。
      #
      # 入力スロットの並びとウィジェットの並びはノード定義に一致させる必要があり、
      # 崩れるとSend to Workflowが動かなくなる。
      # UIで開くまで気付けないため、ここに一箇所だけ定義して末尾の`tests.lora-loader`で検証する。
      #
      # UNETにだけ作用するLoRAを扱うワークフローでは、
      # `clipLink`を省略してCLIPを繋がずに使う。
      mkLoraLoader =
        {
          id,
          pos,
          order,
          title ? null,
          # MODEL入力へ繋ぐリンクID。
          modelLink,
          # CLIP入力へ繋ぐリンクID。nullならCLIPは未接続にする。
          clipLink ? null,
          # MODEL出力から出るリンクIDのリスト。
          modelLinks,
          # CLIP出力から出るリンクIDのリスト。
          clipLinks ? [ ],
        }:
        mkNode {
          inherit
            id
            pos
            order
            title
            ;
          type = "Lora Loader (LoraManager)";
          # フロントエンドがLoRA一覧の領域を確保するため最低でもこの程度の高さで描画される。
          # 実際の描画がこれを上回った場合の場所は、
          # `lib/overlap.nix`の`growHeights`が見込んで空けさせている。
          size = [
            385
            350
          ];
          inputs = [
            (mkInput "model" "MODEL" modelLink)
            # textウィジェットに対応する入力スロット。
            # ソケットへ繋がずウィジェットとして使うので`link`はnullのまま。
            {
              name = "text";
              type = "AUTOCOMPLETE_TEXT_LORAS";
              widget = {
                name = "text";
              };
              link = null;
            }
            # shape 7はoptionalの意味。
            ((mkInput "clip" "CLIP" clipLink) // { shape = 7; })
            # 他のLoRAノードから積み上げる時だけ使うオプション入力。
            {
              name = "lora_stack";
              type = "LORA_STACK";
              shape = 7;
              link = null;
            }
          ];
          outputs = [
            (mkOutput "MODEL" "MODEL" modelLinks)
            (mkOutput "CLIP" "CLIP" clipLinks)
            # LoRAのトリガーワードと適用したLoRAの一覧を文字列で出す補助出力。
            # プロンプトへ繋ぐ使い方があるが、ここでは使わないので未接続にする。
            (mkOutput "trigger_words" "STRING" [ ])
            (mkOutput "loaded_loras" "STRING" [ ])
          ];
          widgets = [
            # __lm_autocomplete_meta_text
            # (テキスト補完のメタデータ。対応するテキストウィジェット名を持つ隠しウィジェット)
            {
              version = 1;
              textWidgetName = "text";
            }
            "" # text(`<lora:名前:強度>`形式のLoRA指定)
            [ ] # loras(LoRAごとの名前と強度と有効状態のリスト。Send to Workflowが書き込む)
          ];
        };
      mkWorkflow =
        {
          nodes,
          links,
          app ? null,
        }:
        {
          inherit nodes links;
          last_node_id = lib.foldl' lib.max 0 (map (node: node.id) nodes);
          last_link_id = lib.foldl' lib.max 0 (map lib.head links);
          groups = [ ];
          config = { };
          extra = lib.optionalAttrs (app != null) {
            # App Mode向けの入力定義は保持しつつ、通常はNode Graphで開く。
            linearMode = false;
            linearData = app;
          };
          version = 0.4;
        };

      # checkpoint読み込み、LoRA適用、プロンプトエンコードの共通部分。
      # どのワークフローも同じノードIDとリンクIDで始まる。
      # リンク: 28=MODEL→LoraLoader, 29=CLIP→LoraLoader,
      # 1=MODEL→KSampler, 2/3=CLIP→TextEncode,
      # 4/5=CONDITIONING→KSampler, 6=LATENT→KSampler
      # 後段の構成によっては同じ出力を追加のノードにも繋ぐので、
      # 追加のリンクIDを引数で受け取る。
      # MODELとCLIPの追加リンクはLoRA適用後のLoraLoader(ノード16)から出る。
      #
      # ここが使うのはノードID 1から5と16、
      # リンクID 1から8(`withEmptyLatent = false`なら6を除く)と28/29なので、
      # 呼び出し元はこれらを避けて番号を振る。
      # LoraLoaderのノード16とリンク28/29には余裕がない。
      # 最も多くのノードを使う`lib/standard.nix`はノード15とリンク27まで使い切っていて、
      # これらはちょうど次の空き番号だからで、
      # 呼び出し元がノードやリンクを1つ足すだけで自然に衝突する。
      # 衝突した場合は`lib/duplicate.nix`の検証が評価時に検出する。
      #
      # img2imgのようにEmptyLatentImage以外からLATENTを供給する場合は、
      # `withEmptyLatent = false`にして、
      # 呼び出し元が代替ノードからリンク6をKSamplerへ張る。
      promptNodes =
        {
          width ? defaultWidth,
          height ? defaultHeight,
          # falseにするとEmptyLatentImage(ノード4)を生成しない。
          withEmptyLatent ? true,
          # img2imgでは1未満にして元画像の構図を残す。
          # 1未満ならKSamplerではなくKSamplerAdvancedを使い、
          # 対応する`start_at_step`へ変換して配置する。
          denoise ? 1,
          # withEmptyLatent = falseで代替ノードを複数挟む場合に、
          # KSamplerのorderを後ろへずらすための値。
          samplerOrder ? 5,
          extraModelLinks ? [ ],
          extraClipLinks ? [ ],
          extraVaeLinks ? [ ],
          extraPositiveLinks ? [ ],
          extraNegativeLinks ? [ ],
        }:
        [
          (mkNode {
            id = 1;
            type = "CheckpointLoaderSimple";
            pos = [
              (-40)
              20
            ];
            size = [
              385
              98
            ];
            order = 0;
            outputs = [
              (mkOutput "MODEL" "MODEL" [ 28 ])
              (mkOutput "CLIP" "CLIP" [ 29 ])
              (mkOutput "VAE" "VAE" ([ 8 ] ++ extraVaeLinks))
            ];
            widgets = [ checkpoint ];
          })
          # オプショナルなLoRA適用。
          (mkLoraLoader {
            id = 16;
            pos = [
              (-40)
              200
            ];
            order = 1;
            modelLink = 28;
            clipLink = 29;
            modelLinks = [ 1 ] ++ extraModelLinks;
            clipLinks = [
              2
              3
            ]
            ++ extraClipLinks;
          })
          (mkNode {
            id = 2;
            type = "CLIPTextEncode";
            # ポジティブとネガティブはどちらも`CLIPTextEncode`の`text`なので、
            # 名前で区別できるのはこのタイトルだけである。
            # `workflow/cli.nix`のコマンドは衝突したウィジェット名をタイトルへ譲るので、
            # ここが無いと`--node2-text`のようなフラグになる。
            # `anima-standard`が自前で置いている同じ役割のノードと文言も揃える。
            title = "Positive Prompt";
            pos = [
              420
              60
            ];
            size = [
              420
              160
            ];
            order = 2;
            inputs = [ (mkInput "clip" "CLIP" 2) ];
            outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" ([ 4 ] ++ extraPositiveLinks)) ];
            widgets = [ positivePrompt ];
          })
          (mkNode {
            id = 3;
            type = "CLIPTextEncode";
            title = "Negative Prompt";
            pos = [
              420
              280
            ];
            size = [
              420
              160
            ];
            order = 3;
            inputs = [ (mkInput "clip" "CLIP" 3) ];
            outputs = [ (mkOutput "CONDITIONING" "CONDITIONING" ([ 5 ] ++ extraNegativeLinks)) ];
            widgets = [ negativePrompt ];
          })
        ]
        ++ lib.optional withEmptyLatent (mkNode {
          id = 4;
          type = "EmptyLatentImage";
          pos = [
            420
            500
          ];
          size = [
            315
            106
          ];
          order = 4;
          outputs = [ (mkOutput "LATENT" "LATENT" [ 6 ]) ];
          widgets = [
            width
            height
            1 # batch_size
          ];
        })
        ++ [
          (mkNode {
            id = 5;
            type = if denoise < 1 then "KSamplerAdvanced" else "KSampler";
            pos = [
              920
              200
            ];
            # KSamplerAdvancedはウィジェットが3つ多い分だけ背が高い。
            size = [
              315
              (if denoise < 1 then 334 else 262)
            ];
            order = samplerOrder;
            inputs = [
              (mkInput "model" "MODEL" 1)
              (mkInput "positive" "CONDITIONING" 4)
              (mkInput "negative" "CONDITIONING" 5)
              (mkInput "latent_image" "LATENT" 6)
            ];
            outputs = [ (mkOutput "LATENT" "LATENT" [ 7 ]) ];
            widgets =
              if denoise < 1 then
                [ "enable" ] # add_noise
                ++ seedWidgets
                ++ [
                  baseSteps # steps
                  5.5 # cfg
                  samplerName
                  schedulerName
                  (startStepForDenoise baseSteps denoise) # start_at_step
                  10000 # end_at_step(実際の終端はstepsで決まる)
                  "disable" # return_with_leftover_noise
                ]
              else
                seedWidgets
                ++ [
                  baseSteps # steps
                  5.5 # cfg
                  samplerName
                  schedulerName
                  denoise
                ];
          })
        ];
      # EmptyLatentImage由来のリンク6を含まない共通リンク。
      # `withEmptyLatent = false`のワークフローはこちらを使って、
      # 代替のLATENT源からリンク6を自前で張る。
      promptBaseLinks = [
        [
          28
          1
          0
          16
          0
          "MODEL"
        ]
        [
          29
          1
          1
          16
          2
          "CLIP"
        ]
        [
          1
          16
          0
          5
          0
          "MODEL"
        ]
        [
          2
          16
          1
          2
          0
          "CLIP"
        ]
        [
          3
          16
          1
          3
          0
          "CLIP"
        ]
        [
          4
          2
          0
          5
          1
          "CONDITIONING"
        ]
        [
          5
          3
          0
          5
          2
          "CONDITIONING"
        ]
        [
          7
          5
          0
          6
          0
          "LATENT"
        ]
        [
          8
          1
          2
          6
          1
          "VAE"
        ]
      ];
      promptLinks = promptBaseLinks ++ [
        [
          6
          4
          0
          5
          3
          "LATENT"
        ]
      ];
    in
    {
      inherit
        mkNode
        mkInput
        mkOutput
        mkLoraLoader
        mkAppInput
        mkAppInputWith
        mkWorkflow
        mkFilenamePrefix
        mkFilenamePrefixWith
        promptNodes
        promptBaseLinks
        promptLinks
        seedWidgets
        samplerName
        schedulerName
        animaSizeMultiple
        baseSteps
        animaBaseSteps
        qwenImageEditResolution
        stepsForDenoise
        startStepForDenoise
        ;
    };

  # 実装のテスト。全ての表明を通ると`true`になる。
  tests = {
    # App Modeの入力と出力の定義の形式を検証する。
    app-mode =
      let
        builder = self;

        appMeta = {
          inputs = [ (builder.mkAppInput 1 "seed") ];
          outputs = [ 1 ];
        };
        appWorkflow = builder.mkWorkflow {
          nodes = [
            (builder.mkNode {
              id = 1;
              type = "TestNode";
              pos = [
                0
                0
              ];
              size = [
                10
                10
              ];
              order = 0;
            })
          ];
          links = [ ];
          app = appMeta;
        };
      in
      # App Mode入力は[ノードID ウィジェット名 設定?]の配列で表現される。
      assert lib.assertMsg (
        builder.mkAppInput 1 "seed" == [
          1
          "seed"
        ]
      ) "App Mode入力の形式が想定と違います";
      assert lib.assertMsg (
        builder.mkAppInputWith 1 "seed" { height = 100; } == [
          1
          "seed"
          { height = 100; }
        ]
      ) "設定付きApp Mode入力の形式が想定と違います";
      assert lib.assertMsg (
        appWorkflow.extra.linearMode == false && appWorkflow.extra.linearData == appMeta
      ) "App Mode定義がextraへ反映されていません";
      true;
    # denoiseの強さがサンプラーの選択とステップ数へ変換されることを検証する。
    denoise =
      let
        builder = self;

        findNode = nodes: id: lib.findFirst (node: node.id == id) null nodes;

        # img2img向けの構成で、denoiseを1未満にしたもの。
        img2imgSampler = findNode (builder.promptNodes {
          withEmptyLatent = false;
          samplerOrder = 7;
          denoise = 0.5;
        }) 5;
      in
      # denoise 1未満はKSamplerAdvancedになり、
      # 強さは実行ステップ数と連動する`start_at_step`として表される。
      assert lib.assertMsg (
        img2imgSampler.type == "KSamplerAdvanced"
      ) "denoise 1未満なのにKSamplerAdvancedになっていません";
      assert lib.assertMsg (
        img2imgSampler.widgets_values == [
          "enable"
          0
          "randomize"
          28
          5.5
          "euler_ancestral"
          "normal"
          14
          10000
          "disable"
        ]
      ) "denoiseがstart_at_stepへ変換されていません";
      assert lib.assertMsg (
        (findNode (builder.promptNodes { }) 5).type == "KSampler"
      ) "denoise 1なのにKSamplerになっていません";
      # `基準のsteps * denoise`がちょうど0.5になる組み合わせ。
      # 切り捨てなので常に小さい側へ倒れ、doubleの表現誤差に結果が左右されない。
      assert lib.assertMsg (
        builder.stepsForDenoise 30 0.35 == 10
        && builder.stepsForDenoise 30 0.55 == 16
        && builder.stepsForDenoise 30 0.75 == 22
      ) "0.5の境界に乗るdenoiseの丸めが切り捨てになっていません";
      # 各ワークフローが実際に使っている組み合わせ。
      # ここが変わると生成されるステップ数が黙って変わる。
      assert lib.assertMsg (
        builder.stepsForDenoise builder.baseSteps 0.45 == 12
        && builder.stepsForDenoise builder.baseSteps 0.5 == 14
        && builder.stepsForDenoise builder.animaBaseSteps 0.3 == 9
      ) "実際に使っているdenoiseのステップ数が想定と違います";
      assert lib.assertMsg (
        builder.startStepForDenoise builder.baseSteps 0.5 == 14
        && builder.startStepForDenoise builder.animaBaseSteps 0.5 == 15
      ) "実際に使っているdenoiseのstart_at_stepが想定と違います";
      assert lib.assertMsg (
        builder.stepsForDenoise builder.baseSteps 1 == builder.baseSteps
      ) "denoise 1なのに基準のステップ数と違います";
      # どのワークフローも通らない下限のクランプ。
      # 検証がなければ壊れても気付けない。
      assert lib.assertMsg (builder.stepsForDenoise builder.baseSteps 0.01 == 1) "ステップ数が1未満へ落ちています";
      true;
    # 保存ノードの`filename_prefix`の形式を検証する。
    # 置換パターンはサーバ側のfolder_pathsの仕様に合わせている。
    filename-prefix =
      let
        builder = self;
      in
      assert lib.assertMsg (
        builder.mkFilenamePrefix "test" == "test/test-%year%-%month%-%day%-%hour%-%minute%-%second%"
      ) "filename_prefixの形式が想定と違います";
      assert lib.assertMsg (
        builder.mkFilenamePrefixWith "test" "-x"
        == "test/test-x-%year%-%month%-%day%-%hour%-%minute%-%second%"
      ) "サフィックス付きfilename_prefixの形式が想定と違います";
      true;
    # `builder.mkLoraLoader`が作るノードの形状を検証する。
    #
    # `Lora Loader (LoraManager)`は入力スロットの並びとウィジェットの並びが、
    # LoRA Manager側のノード定義と一致していないと、
    # 管理画面のSend to Workflowがこのノードを見つけられず動かなくなる。
    # 他のassertionはリンクやorderしか見ないため、
    # 綴りや並びが崩れてもビルドは通ってUIで開くまで気付けない。
    lora-loader =
      let
        builder = self;
        # CLIPも通す場合。
        withClip = builder.mkLoraLoader {
          id = 16;
          pos = [
            0
            0
          ];
          order = 1;
          modelLink = 28;
          clipLink = 29;
          modelLinks = [ 1 ];
          clipLinks = [
            2
            3
          ];
        };
        # UNETにだけ作用するLoRA向けにCLIPを繋がない場合。
        withoutClip = builder.mkLoraLoader {
          id = 31;
          title = "LoRA(high noise用)";
          pos = [
            0
            0
          ];
          order = 1;
          modelLink = 38;
          modelLinks = [ 1 ];
        };
        slotNames = map (slot: slot.name);
        slotTypes = map (slot: slot.type);
      in
      assert lib.assertMsg (withClip.type == "Lora Loader (LoraManager)") "ノード型が想定と違います";
      assert lib.assertMsg (
        slotNames withClip.inputs == [
          "model"
          "text"
          "clip"
          "lora_stack"
        ]
      ) "入力スロットの名前か並びが想定と違います";
      assert lib.assertMsg (
        slotTypes withClip.inputs == [
          "MODEL"
          "AUTOCOMPLETE_TEXT_LORAS"
          "CLIP"
          "LORA_STACK"
        ]
      ) "入力スロットの型が想定と違います";
      assert lib.assertMsg (
        slotNames withClip.outputs == [
          "MODEL"
          "CLIP"
          "trigger_words"
          "loaded_loras"
        ]
      ) "出力スロットの名前か並びが想定と違います";
      # LoRA一覧の内部状態、テキスト、有効なLoRAのリストの順。
      assert lib.assertMsg (
        withClip.widgets_values == [
          {
            version = 1;
            textWidgetName = "text";
          }
          ""
          [ ]
        ]
      ) "ウィジェットの内容か並びが想定と違います";
      # textスロットはウィジェットと連動する入力なのでwidget属性が要る。
      assert lib.assertMsg (
        (lib.elemAt withClip.inputs 1).widget.name == "text"
      ) "textスロットのwidget名が想定と違います";
      # オプション入力はshape 7で描かれる。
      assert lib.assertMsg (
        (lib.elemAt withClip.inputs 2).shape == 7 && (lib.elemAt withClip.inputs 3).shape == 7
      ) "オプション入力のshapeが想定と違います";
      assert lib.assertMsg (
        (lib.elemAt withClip.inputs 0).link == 28 && (lib.elemAt withClip.inputs 2).link == 29
      ) "入力リンクが引数どおりに設定されていません";
      assert lib.assertMsg (
        (lib.elemAt withClip.outputs 0).links == [ 1 ]
        &&
          (lib.elemAt withClip.outputs 1).links == [
            2
            3
          ]
      ) "出力リンクが引数どおりに設定されていません";
      # clipLink省略時もスロット自体は同じ並びで残し、リンクだけ未接続にする。
      assert lib.assertMsg (
        slotNames withoutClip.inputs == slotNames withClip.inputs
      ) "clipLink省略時に入力スロットの並びが変わりました";
      assert lib.assertMsg (
        (lib.elemAt withoutClip.inputs 2).link == null && (lib.elemAt withoutClip.outputs 1).links == [ ]
      ) "clipLink省略時にCLIPが未接続になっていません";
      assert lib.assertMsg (withoutClip.title == "LoRA(high noise用)") "titleが反映されていません";
      assert lib.assertMsg (!(withClip ? title)) "title未指定なのにtitleが付いています";
      true;
    # `builder.mkNode`がオプション引数を省略した時の形状を検証する。
    node =
      let
        builder = self;
        # オプション引数を全て省略した素のノード。
        plainNode = builder.mkNode {
          id = 1;
          type = "TestNode";
          pos = [
            0
            0
          ];
          size = [
            10
            10
          ];
          order = 0;
        };
      in
      # mkNodeのオプション属性は省略時に属性ごと付かない。
      # nullのまま出力するとComfyUIのJSONとして意味が変わり得る。
      assert lib.assertMsg (
        !(plainNode ? widgets_values) && !(plainNode ? title)
      ) "省略したオプション属性が素のノードに付いています";
      assert lib.assertMsg (
        plainNode.properties."Node name for S&R" == "TestNode"
      ) "S&R用のノード型名が設定されていません";
      true;
    # 全ワークフローの土台である`builder.promptNodes`と`builder.promptLinks`を検証する。
    #
    # 引数がノードへ反映されることと、
    # 呼び出し元が最低限の後続ノードを足した状態で、
    # ID重複・リンク・order・重なりの各検証を通ることを確かめる。
    prompt =
      let
        builder = self;
        duplicate = import ./duplicate.nix { inherit lib; };
        link = import ./link.nix { inherit lib; };
        order = import ./order.nix { inherit lib; };
        overlap = import ./overlap.nix { inherit lib; };

        findNode = nodes: id: lib.findFirst (node: node.id == id) null nodes;
        outputLinks =
          nodes: id: slot:
          (lib.elemAt (findNode nodes id).outputs slot).links;

        # `promptNodes`が要求する後続ノード(リンク7と8の受け手)を足した最小構成。
        # 呼び出し元が最低限やることの再現になっている。
        promptWorkflow = builder.mkWorkflow {
          nodes = builder.promptNodes { } ++ [
            (builder.mkNode {
              id = 6;
              type = "VAEDecode";
              pos = [
                1290
                200
              ];
              size = [
                210
                46
              ];
              order = 6;
              inputs = [
                (builder.mkInput "samples" "LATENT" 7)
                (builder.mkInput "vae" "VAE" 8)
              ];
              outputs = [ (builder.mkOutput "IMAGE" "IMAGE" [ ]) ];
            })
          ];
          links = builder.promptLinks;
        };

        # img2img向けの構成。EmptyLatentImageを省いてKSamplerのorderをずらす。
        img2imgNodes = builder.promptNodes {
          withEmptyLatent = false;
          samplerOrder = 7;
          denoise = 0.5;
        };

        # 追加リンクは共通ノードの出力の既定リンクの後ろへ足される。
        extraNodes = builder.promptNodes {
          extraModelLinks = [ 90 ];
          extraClipLinks = [ 91 ];
          extraVaeLinks = [ 92 ];
          extraPositiveLinks = [ 93 ];
          extraNegativeLinks = [ 94 ];
        };
      in
      # 共通部品は使用するIDの範囲をコメントで約束している。
      # 範囲が変わると全ワークフローの番号の振り方に影響するため固定する。
      assert lib.assertMsg (
        promptWorkflow.last_node_id == 16 && promptWorkflow.last_link_id == 29
      ) "共通部品の最大ノードID・リンクIDが想定と違います";
      assert lib.assertMsg (promptWorkflow.extra == { }) "app未指定の時にextraが空になっていません";
      # 共通部品自体が各検証を通ることの確認。
      assert lib.assertMsg (duplicate.duplicateIdErrors promptWorkflow == [ ]) "共通部品のIDが重複しています";
      assert lib.assertMsg (link.invalidReferences promptWorkflow == [ ]) "共通部品のリンクが不整合です";
      assert lib.assertMsg (order.orderErrors promptWorkflow == [ ]) "共通部品のorderが不整合です";
      assert lib.assertMsg (overlap.overlappingNodePairs promptWorkflow.nodes == [ ]) "共通部品のノードが重なっています";
      assert lib.assertMsg (lib.all (
        node: node.id != 4
      ) img2imgNodes) "withEmptyLatent = falseなのにEmptyLatentImageが生成されています";
      assert lib.assertMsg ((findNode img2imgNodes 5).order == 7) "samplerOrderがKSamplerへ反映されていません";
      assert lib.assertMsg (
        outputLinks extraNodes 16 0 == [
          1
          90
        ]
        &&
          outputLinks extraNodes 16 1 == [
            2
            3
            91
          ]
      ) "MODEL・CLIPの追加リンクがLoraLoaderへ反映されていません";
      assert lib.assertMsg (
        outputLinks extraNodes 1 2 == [
          8
          92
        ]
      ) "VAEの追加リンクがCheckpointLoaderへ反映されていません";
      assert lib.assertMsg (
        outputLinks extraNodes 2 0 == [
          4
          93
        ]
        &&
          outputLinks extraNodes 3 0 == [
            5
            94
          ]
      ) "CONDITIONINGの追加リンクがCLIPTextEncodeへ反映されていません";
      true;
  };
in
assert lib.all lib.id (lib.attrValues tests);
self
