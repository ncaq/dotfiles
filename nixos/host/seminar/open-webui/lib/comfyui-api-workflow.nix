/**
  Open WebUIへ環境変数として渡すComfyUIのAPI形式ワークフローを、
  評価時に検査する。

  ComfyUIのワークフローにはUI形式とAPI形式があり、
  bulletが持つUI形式は`comfyui/workflow/validate.nix`が、
  リンク切れやID重複やウィジェットの並びを機械的に弾いている。
  API形式は`inputs`へ名前付きで書く別の構造なのでその検査を流用できない。

  検査が無いと、
  接続先のIDを打ち間違えても、
  `workflowNodes`が想定外の`type`を書いていても、
  評価は素通りしてComfyUIの実行時にしか分からない。

  しかもOpen WebUI経由では最も気付きにくい壊れ方をする。
  画像を返す保存ノードへ至る経路だけがバリデーションで落ちて、
  そこを通らないノードは生き残るため、
  全体の`status`は`success`のまま画像だけが返らない。

  `checks`が検査そのもので、項目ごとにエラー文字列のリストを返す。
  `assertions`はそれをNixOSのassertionへ包む。
  分けてあるのは末尾の`tests`が項目ごとに表明できるようにするためで、
  `comfyui/workflow/lib/link.nix`とその末尾のテストの関係に揃えている。
  テストは配線の漏れを見るために`assertions`の側も通す。

  ```nix
  assertions = (import ./lib/comfyui-api-workflow.nix { inherit lib; }).assertions {
    name = "画像生成";
    inherit workflow workflowNodes;
    validTypes = [ "model" "prompt" "seed" ];
    requiredTypes = [ "model" "prompt" ];
  };
  ```
*/
{ lib }:
let
  self =
    let
      # Open WebUIが画像として拾う出力ノード。
      # `PreviewAny`は画像を返さないが、
      # 指示文のリライト結果をUIから確認するために置いてあり、
      # ComfyUIから見れば同じく実行の起点になるので到達性の検査では出力として扱う。
      outputClassTypes = [
        "SaveImage"
        "PreviewImage"
        "PreviewAny"
      ];

      # API形式では他のノードへの接続を`[ノードID, 出力スロット]`で表す。
      #
      # 第2要素が整数であることまで見る。
      # 先頭が文字列の2要素リストという条件だけだと、
      # ウィジェットが同じ形の値を取った時に接続と誤認して存在しないノードを報告し、
      # 逆にスロット番号を`[ "7" "0" ]`と文字列で書き間違えても素通りする。
      isLink =
        value:
        lib.isList value
        && lib.length value == 2
        && lib.isString (lib.elemAt value 0)
        && lib.isInt (lib.elemAt value 1);

      nodeInputs = workflow: id: workflow.${id}.inputs or { };

      # ノードが直接依存する他のノードのID。
      dependencies =
        workflow: id:
        lib.pipe (nodeInputs workflow id) [
          lib.attrValues
          (lib.filter isLink)
          (map (value: lib.elemAt value 0))
        ];

      checks =
        {
          workflow,
          workflowNodes,
          # `workflowNodes`が書いてよい`type`。
          # Open WebUI側のフォームが実際に値を入れるものだけを呼び出し側が列挙する。
          validTypes,
          # 無いとUIの入力が黙って無視される`type`。
          requiredTypes,
        }:
        let
          declaredTypes = map (entry: entry.type) workflowNodes;

          # 出力ノードから依存を辿って到達できるノード。
          #
          # ComfyUIは出力ノードから逆向きに辿った必要なノードだけを実行する。
          # 経路から外れたノードは評価もCIも通ったまま一度も実行されない。
          reachable =
            let
              step =
                visited:
                let
                  next = lib.unique (visited ++ lib.concatMap (dependencies workflow) visited);
                in
                if lib.length next == lib.length visited then visited else step next;
              outputs = lib.filter (id: lib.elem (workflow.${id}.class_type or null) outputClassTypes) (
                lib.attrNames workflow
              );
            in
            step outputs;
        in
        {
          # ノードの形そのものの検査。
          # `inputs`を`or`無しで辿ると`attribute 'inputs' missing`になり、
          # このモジュールが無くそうとしているのと同種の読めないエラーに落ちる。
          malformedNodes = lib.filter (id: !(workflow.${id} ? class_type) || !(workflow.${id} ? inputs)) (
            lib.attrNames workflow
          );

          # 存在しないノードへの接続。
          danglingLinks = lib.concatMap (
            id:
            lib.concatMap (
              inputName:
              let
                value = (nodeInputs workflow id).${inputName};
              in
              lib.optional (
                isLink value && !(workflow ? ${lib.elemAt value 0})
              ) "${id}.${inputName} -> ${lib.elemAt value 0}"
            ) (lib.attrNames (nodeInputs workflow id))
          ) (lib.attrNames workflow);

          # 出力ノードから到達できないノード。
          orphanNodes = lib.filter (id: !(lib.elem id reachable)) (lib.attrNames workflow);

          # `workflowNodes`が存在しないノードを指しているもの。
          missingNodes = lib.concatMap (
            entry:
            map (nodeId: "${entry.type} -> ${nodeId}") (
              lib.filter (nodeId: !(workflow ? ${nodeId})) entry.node_ids
            )
          ) workflowNodes;

          # 対象ノードが`key`を持たないもの。
          # 存在しないノードは`missingNodes`が報告するのでここでは除く。
          missingKeys = lib.concatMap (
            entry:
            map (nodeId: "${entry.type} -> ${nodeId}.${entry.key}") (
              lib.filter (
                nodeId: (workflow ? ${nodeId}) && !((nodeInputs workflow nodeId) ? ${entry.key})
              ) entry.node_ids
            )
          ) workflowNodes;

          # Open WebUI側のフォームに無い`type`。
          #
          # 実際に2回踏んだ不具合はどちらもこの形だった。
          # `negative_prompt`は`ComfyUIEditImageForm`が属性を持たないため実行時に落ち、
          # `steps`はフィールドはあっても既定が`None`のまま誰も値を入れなかった。
          # 接続の整合性だけを見る検査では両方とも素通りする。
          unknownTypes = lib.unique (lib.filter (type: !(lib.elem type validTypes)) declaredTypes);

          # 書き忘れた`type`。
          # 例えば`prompt`の行が消えるとUIの入力が無視されて初期値で生成され、
          # 画像は正常に返るので誰も気付けない。
          absentTypes = lib.filter (type: !(lib.elem type declaredTypes)) requiredTypes;

          # 同じ`type`を2度書いたもの。
          # Open WebUIは後勝ちで解釈するので、前の行が黙って効かなくなる。
          duplicateTypes = lib.unique (
            lib.filter (type: lib.count (other: other == type) declaredTypes > 1) declaredTypes
          );

          # 引数同士の矛盾。
          #
          # `validTypes`に無い`type`を`requiredTypes`へ書くと、
          # ワークフローに書けば`unknownTypes`で落ち、
          # 書かなければ`absentTypes`で落ちる、どうやっても通らない設定になる。
          # 2つの別々の項目として報告されるので、
          # 原因が引数の側にあることに気付けない。
          contradictoryTypes = lib.unique (lib.filter (type: !(lib.elem type validTypes)) requiredTypes);
        };

      assertions =
        {
          name,
          workflow,
          workflowNodes,
          validTypes,
          requiredTypes,
        }:
        let
          result = checks {
            inherit
              workflow
              workflowNodes
              validTypes
              requiredTypes
              ;
          };
          # 検査の項目名から、非空だった時に出す文章への対応表。
          #
          # `checks`の結果の側を`lib.mapAttrsToList`で走査するので、
          # ここに無い項目を`checks`へ足すと`missing attribute`で即座に落ちる。
          # リストを並べる形にすると、
          # 検査を足して対応表への追加を忘れた時に、
          # その検査が黙って発火しないまま残ってしまう。
          # このモジュール自体が「緩んだこと自体を誰も検出できない」状態を無くすためのものなので、
          # 対応の漏れも評価時に分かる形にしておく。
          report = {
            malformedNodes = "class_typeかinputsを持たないノードがあります";
            danglingLinks = "存在しないノードへ接続しています";
            orphanNodes = "出力ノードから到達できないノードがあります";
            missingNodes = "workflowNodesが存在しないノードを指しています";
            missingKeys = "workflowNodesが対象ノードの持たない入力を指しています";
            unknownTypes = "workflowNodesがOpen WebUIのフォームに無いtypeを書いています";
            absentTypes = "workflowNodesに必要なtypeがありません";
            duplicateTypes = "workflowNodesが同じtypeを重複して書いています";
            contradictoryTypes = "requiredTypesがvalidTypesに無いtypeを要求しています";
          };
        in
        lib.mapAttrsToList (key: items: {
          assertion = items == [ ];
          message = "${name}の${report.${key}}: ${lib.concatStringsSep ", " items}";
        }) result;
    in
    {
      inherit checks assertions;
    };

  # 下の`tests`が共有する入力と呼び出し方。
  #
  # この検査はbullet側の`comfyui/workflow/validate.nix`にあたるもので、
  # あちらの検査ロジックが`comfyui/workflow/lib/link.nix`の末尾のような対のテストで守られているのに対し、
  # こちらは「実際のワークフローで一度通した」だけだった。
  # 検査が緩んでも、緩んだこと自体は誰も検出できない状態になる。
  # 正常なワークフローを拒否せず、壊れたワークフローを見逃さないことを、
  # 検査項目ごとの属性で確かめる。
  fixture = rec {
    inherit (self) checks assertions;

    # 実際のワークフローの構造を最小限に写したもの。
    # ローダからサンプラを経て保存ノードへ至る、という骨格は同じにする。
    validWorkflow = {
      "1" = {
        class_type = "UNETLoader";
        inputs.unet_name = "example.safetensors";
      };
      "2" = {
        class_type = "KSampler";
        inputs = {
          seed = 0;
          model = [
            "1"
            0
          ];
        };
      };
      "3" = {
        class_type = "SaveImage";
        inputs = {
          filename_prefix = "example";
          images = [
            "2"
            0
          ];
        };
      };
    };

    # 2つ目のサンプラ。
    # `seed`のように1つの入力を複数のノードへ配る形を再現するために置く。
    # 実際の`image-generation.nix`は`seed`を`[ "7" "14" "17" ]`の3つへ、
    # `image-edit.nix`は`image`を`[ "4" "17" "18" ]`の3つへ配っている。
    multiNodeWorkflow = lib.recursiveUpdate validWorkflow {
      "4" = {
        class_type = "KSampler";
        inputs = {
          seed = 0;
          model = [
            "2"
            0
          ];
        };
      };
      "3".inputs.images = [
        "4"
        0
      ];
    };

    multiNodes = [
      {
        type = "model";
        key = "unet_name";
        node_ids = [ "1" ];
      }
      {
        type = "seed";
        key = "seed";
        node_ids = [
          "2"
          "4"
        ];
      }
    ];

    validNodes = [
      {
        type = "model";
        key = "unet_name";
        node_ids = [ "1" ];
      }
      {
        type = "seed";
        key = "seed";
        node_ids = [ "2" ];
      }
    ];

    validTypes = [
      "model"
      "seed"
    ];
    requiredTypes = [ "model" ];

    run =
      {
        workflow ? validWorkflow,
        workflowNodes ? validNodes,
        types ? validTypes,
        required ? requiredTypes,
      }:
      checks {
        inherit workflow workflowNodes;
        validTypes = types;
        requiredTypes = required;
      };

    # 全ての検査項目が空であること。
    allEmpty = result: lib.all (items: items == [ ]) (lib.attrValues result);

    # 呼び出し側が実際に使うのは`assertions`の方なので、そちらも通す。
    runAssertions =
      {
        workflow ? validWorkflow,
        workflowNodes ? validNodes,
        types ? validTypes,
        required ? requiredTypes,
      }:
      assertions {
        name = "テスト";
        inherit workflow workflowNodes;
        validTypes = types;
        requiredTypes = required;
      };

    failed = entries: lib.filter (entry: !entry.assertion) entries;
  };

  # 実装のテスト。全ての表明を通ると`true`になる。
  tests = {
    # 呼び出し側が実際に使う`assertions`の側。
    # `checks`だけを叩いていると、
    # 検査を足して対応表への配線を忘れた場合にテストが通り続けてしまう。
    assertions =
      let
        inherit (fixture)
          validWorkflow
          run
          runAssertions
          failed
          ;
      in
      assert lib.assertMsg (failed (runAssertions { }) == [ ]) "正常なワークフローでassertionが落ちました";

      # 全ての検査項目がassertionへ配線されていること。
      #
      # 数の一致だけでは足りない。
      # `assertions`は`checks`の結果の側を走査するので、
      # 対応表に無い項目があっても数は必ず一致する。
      # `message`は`assertion`が真の間は評価されないため、
      # ここで文字列として強制して初めて`missing attribute`が出る。
      assert lib.assertMsg (
        lib.length (runAssertions { }) == lib.length (lib.attrNames (run { }))
      ) "checksの項目数とassertionsの数が一致しません";
      assert lib.assertMsg (lib.all (entry: lib.isString entry.message) (
        runAssertions { }
      )) "assertionのメッセージを組み立てられませんでした";

      # 壊した時にメッセージへ壊した箇所が載ること。
      #
      # 接続先を存在しないIDにすると、
      # そのノードが経路から外れるので到達性の側でも落ちる。
      # 件数は決め打ちにせず、
      # 接続の項目が壊した先を名指ししていることだけを見る。
      assert lib.assertMsg (
        let
          broken = failed (runAssertions {
            workflow = lib.recursiveUpdate validWorkflow {
              "3".inputs.images = [
                "99"
                0
              ];
            };
          });
        in
        lib.any (entry: lib.hasInfix "3.images -> 99" entry.message) broken
      ) "assertionのメッセージに壊した接続先が載りませんでした";
      true;
    # 接続(`[ノードID スロット番号]`)の検査が、
    # 存在しないノードへの接続を見逃さず、接続でない値を接続と誤認しないこと。
    link =
      let
        inherit (fixture) validWorkflow run;
      in
      # 接続先のIDを打ち間違えた場合。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "3".inputs.images = [
              "99"
              0
            ];
          };
        }).danglingLinks != [ ]
      ) "存在しないノードへの接続を見逃しました";

      # ウィジェットの値が接続と同じ形をしていても接続とみなさないこと。
      # スロット番号が整数でないので接続ではない。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "1".inputs.unet_name = [
              "a"
              "b"
            ];
          };
        }).danglingLinks == [ ]
      ) "第2要素が整数でない値を接続と誤認しました";

      # 3要素のリストも接続ではない。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "1".inputs.unet_name = [
              "a"
              0
              1
            ];
          };
        }).danglingLinks == [ ]
      ) "3要素のリストを接続と誤認しました";

      # 第1要素が文字列でない2要素リストも接続ではない。
      # `lib.isString`のガードを外すと、
      # ノードIDとして文字列補間しようとして読めない型エラーになる。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "1".inputs.unet_name = [
              0
              0
            ];
          };
        }).danglingLinks == [ ]
      ) "第1要素が文字列でない値を接続と誤認しました";
      true;
    # ノードとして必要な属性を書き忘れたノードを見逃さないこと。
    malformed =
      let
        inherit (fixture) validWorkflow run;
      in
      # `inputs`を書き忘れたノード。
      assert lib.assertMsg (
        (run {
          workflow = validWorkflow // {
            "4".class_type = "PreviewImage";
          };
        }).malformedNodes == [ "4" ]
      ) "inputsを持たないノードを見逃しました";

      # `class_type`を書き忘れたノード。
      assert lib.assertMsg (
        (run {
          workflow = validWorkflow // {
            "4".inputs = { };
          };
        }).malformedNodes == [ "4" ]
      ) "class_typeを持たないノードを見逃しました";
      true;
    # 出力ノードから辿れないノードを見逃さないこと。
    reachability =
      let
        inherit (fixture) validWorkflow run;
      in
      # スロット番号を文字列で書き間違えた場合。
      #
      # 接続とみなさないので`danglingLinks`には出ないが、
      # その分だけ依存が辿れなくなって参照先が経路から外れる。
      # `isLink`が第2要素の整数性を見る意味は、
      # 書き間違いをこの経路で捕まえることにある。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "2".inputs.model = [
              "1"
              "0"
            ];
          };
        }).orphanNodes == [ "1" ]
      ) "スロット番号の書き間違いが到達性の側で捕まりませんでした";

      # 保存ノードの入力を戻してしまい、間のノードが経路から外れた場合。
      assert lib.assertMsg (
        (run {
          workflow = lib.recursiveUpdate validWorkflow {
            "3".inputs.images = [
              "1"
              0
            ];
          };
        }).orphanNodes == [ "2" ]
      ) "出力ノードから到達できないノードを見逃しました";
      true;
    # `workflowNodes`の`type`がOpen WebUI側のフォームと食い違っていたら見逃さないこと。
    types =
      let
        inherit (fixture) validNodes requiredTypes run;
      in
      # Open WebUI側のフォームに無い`type`を書いた場合。
      # 実際に踏んだ`negative_prompt`と`steps`がこの形だった。
      assert lib.assertMsg (
        (run {
          workflowNodes = validNodes ++ [
            {
              type = "negative_prompt";
              key = "seed";
              node_ids = [ "2" ];
            }
          ];
        }).unknownTypes == [ "negative_prompt" ]
      ) "フォームに無いtypeを見逃しました";

      # 同じ`type`を2行書いた場合も、報告は1度だけにする。
      assert lib.assertMsg (
        (run {
          workflowNodes = validNodes ++ [
            {
              type = "negative_prompt";
              key = "seed";
              node_ids = [ "2" ];
            }
            {
              type = "negative_prompt";
              key = "seed";
              node_ids = [ "2" ];
            }
          ];
        }).unknownTypes == [ "negative_prompt" ]
      ) "フォームに無いtypeを重複して報告しました";

      # 必要な`type`の行を消した場合。
      assert lib.assertMsg (
        (run {
          workflowNodes = lib.filter (entry: entry.type != "model") validNodes;
        }).absentTypes == [ "model" ]
      ) "必要なtypeの欠落を見逃しました";

      # 同じ`type`を2度書いた場合。
      assert lib.assertMsg (
        (run {
          workflowNodes = validNodes ++ [
            {
              type = "seed";
              key = "seed";
              node_ids = [ "2" ];
            }
          ];
        }).duplicateTypes == [ "seed" ]
      ) "重複したtypeを見逃しました";

      # `requiredTypes`が`validTypes`に無い`type`を要求している場合。
      # 引数同士の矛盾なので、ワークフローの側をどう書いても通らない。
      assert lib.assertMsg (
        (run {
          required = requiredTypes ++ [ "nonexistent_type" ];
        }).contradictoryTypes == [ "nonexistent_type" ]
      ) "引数同士の矛盾を見逃しました";
      true;
    # 正常なワークフローを拒否しないこと。
    valid =
      let
        inherit (fixture) run allEmpty;
      in
      assert lib.assertMsg (allEmpty (run { })) "正常なワークフローを拒否しました";
      true;
    # `workflowNodes`がワークフローに無いノードや入力を指していたら見逃さないこと。
    workflow-nodes =
      let
        inherit (fixture)
          validNodes
          multiNodeWorkflow
          multiNodes
          run
          allEmpty
          ;
      in
      # `workflowNodes`が存在しないノードを指す場合。
      assert lib.assertMsg (
        (run {
          workflowNodes = validNodes ++ [
            {
              type = "seed";
              key = "seed";
              node_ids = [ "98" ];
            }
          ];
        }).missingNodes != [ ]
      ) "workflowNodesの存在しないノードを見逃しました";

      # `key`が対象ノードに無い場合。
      assert lib.assertMsg (
        (run {
          workflowNodes = [
            {
              type = "model";
              key = "nonexistent";
              node_ids = [ "1" ];
            }
          ];
        }).missingKeys != [ ]
      ) "対象ノードが持たない入力を見逃しました";

      # `node_ids`が複数ある場合に、2番目以降も見ていること。
      #
      # 実際のワークフローは`seed`も`image`も複数のノードへ配るので、
      # `lib.head entry.node_ids`のように先頭だけを見る実装へ退化すると、
      # production側の主要な形が丸ごと検査されなくなる。
      assert lib.assertMsg (allEmpty (run {
        workflow = multiNodeWorkflow;
        workflowNodes = multiNodes;
      })) "複数のnode_idsを持つ正常なワークフローを拒否しました";

      assert lib.assertMsg (
        (run {
          workflow = multiNodeWorkflow;
          workflowNodes = [
            {
              type = "seed";
              key = "seed";
              node_ids = [
                "2"
                "97"
              ];
            }
          ];
        }).missingNodes == [ "seed -> 97" ]
      ) "node_idsの2番目が存在しないことを見逃しました";

      assert lib.assertMsg (
        (run {
          # `1`はUNETLoaderで`seed`を持たない。
          workflow = multiNodeWorkflow;
          workflowNodes = [
            {
              type = "seed";
              key = "seed";
              node_ids = [
                "2"
                "1"
              ];
            }
          ];
        }).missingKeys == [ "seed -> 1.seed" ]
      ) "node_idsの2番目だけがkeyを持たないことを見逃しました";
      true;
  };
in
assert lib.all lib.id (lib.attrValues tests);
self
