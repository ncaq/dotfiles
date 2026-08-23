/**
  Open WebUIへ環境変数として渡すComfyUIのAPI形式ワークフローを、
  評価時に検査する。

  ComfyUIのワークフローにはUI形式とAPI形式があり、
  bulletが持つUI形式は`comfyui/workflow/lib/validate.nix`が、
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

  `checks`が検査そのもので、エラー文字列のリストを返す純粋な関数群である。
  `assertions`はそれをNixOSのassertionへ包む。
  分けてあるのは`comfyui-api-workflow-test.nix`が`checks`だけを使うためで、
  `comfyui/workflow/lib/link.nix`と`link-test.nix`の関係に揃えている。

  ```nix
  assertions = (import ../../../../lib/comfyui-api-workflow.nix { inherit lib; }).assertions {
    name = "画像生成";
    inherit workflow workflowNodes;
    validTypes = [ "model" "prompt" "seed" ];
    requiredTypes = [ "model" "prompt" ];
  };
  ```
*/
{ lib }:
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
      # このPRで2回踏んだ不具合はどちらもこの形だった。
      # `negative_prompt`は`ComfyUIEditImageForm`が属性を持たないため実行時に落ち、
      # `steps`はフィールドはあっても既定が`None`のまま誰も値を入れなかった。
      # 接続の整合性だけを見る検査では両方とも素通りする。
      unknownTypes = lib.filter (type: !(lib.elem type validTypes)) declaredTypes;

      # 書き忘れた`type`。
      # 例えば`prompt`の行が消えるとUIの入力が無視されて初期値で生成され、
      # 画像は正常に返るので誰も気付けない。
      absentTypes = lib.filter (type: !(lib.elem type declaredTypes)) requiredTypes;

      # 同じ`type`を2度書いたもの。
      # Open WebUIは後勝ちで解釈するので、前の行が黙って効かなくなる。
      duplicateTypes = lib.unique (
        lib.filter (type: lib.count (other: other == type) declaredTypes > 1) declaredTypes
      );
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
      # 空なら通り、非空ならその一覧を添えて落とす項目の対応表。
      report = [
        {
          items = result.malformedNodes;
          text = "class_typeかinputsを持たないノードがあります";
        }
        {
          items = result.danglingLinks;
          text = "存在しないノードへ接続しています";
        }
        {
          items = result.orphanNodes;
          text = "出力ノードから到達できないノードがあります";
        }
        {
          items = result.missingNodes;
          text = "workflowNodesが存在しないノードを指しています";
        }
        {
          items = result.missingKeys;
          text = "workflowNodesが対象ノードの持たない入力を指しています";
        }
        {
          items = result.unknownTypes;
          text = "workflowNodesがOpen WebUIのフォームに無いtypeを書いています";
        }
        {
          items = result.absentTypes;
          text = "workflowNodesに必要なtypeがありません";
        }
        {
          items = result.duplicateTypes;
          text = "workflowNodesが同じtypeを重複して書いています";
        }
      ];
    in
    map (entry: {
      assertion = entry.items == [ ];
      message = "${name}の${entry.text}: ${lib.concatStringsSep ", " entry.items}";
    }) report;
in
{
  inherit checks assertions;
}
