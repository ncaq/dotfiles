{ lib }:
let
  self = {
    invalidReferences =
      workflow:
      let
        findNode = id: lib.findFirst (node: node.id == id) null workflow.nodes;
        findLink = id: lib.findFirst (link: builtins.elemAt link 0 == id) null workflow.links;
        getSlot =
          slots: index:
          if 0 <= index && index < builtins.length slots then builtins.elemAt slots index else null;
        acceptsType =
          slotType: linkType:
          slotType == "*" || linkType == "*" || builtins.elem linkType (lib.splitString "," slotType);
        nodeReferenceErrors = lib.concatMap (
          node:
          lib.concatLists (
            lib.imap0 (
              inputSlot: input:
              let
                link = if input.link == null then null else findLink input.link;
              in
              lib.optional (
                input.link != null
                && (link == null || builtins.elemAt link 3 != node.id || builtins.elemAt link 4 != inputSlot)
              ) "  ノード${toString node.id}の入力${toString inputSlot}が不整合なリンク${toString input.link}を参照しています"
            ) node.inputs
          )
          ++ lib.concatLists (
            lib.imap0 (
              outputSlot: output:
              lib.concatMap (
                linkId:
                let
                  link = findLink linkId;
                in
                lib.optional (
                  link == null || builtins.elemAt link 1 != node.id || builtins.elemAt link 2 != outputSlot
                ) "  ノード${toString node.id}の出力${toString outputSlot}が不整合なリンク${toString linkId}を参照しています"
              ) output.links
            ) node.outputs
          )
        ) workflow.nodes;
        linkEndpointErrors = lib.concatMap (
          link:
          let
            linkId = builtins.elemAt link 0;
            sourceNodeId = builtins.elemAt link 1;
            sourceSlot = builtins.elemAt link 2;
            targetNodeId = builtins.elemAt link 3;
            targetSlot = builtins.elemAt link 4;
            linkType = builtins.elemAt link 5;
            sourceNode = findNode sourceNodeId;
            targetNode = findNode targetNodeId;
            sourceOutput = if sourceNode == null then null else getSlot sourceNode.outputs sourceSlot;
            targetInput = if targetNode == null then null else getSlot targetNode.inputs targetSlot;
          in
          lib.optional (
            sourceOutput == null || !(builtins.elem linkId sourceOutput.links)
          ) "  リンク${toString linkId}の接続元ノード${toString sourceNodeId}の出力${toString sourceSlot}がリンクを参照していません"
          ++ lib.optional (
            targetInput == null || targetInput.link != linkId
          ) "  リンク${toString linkId}の接続先ノード${toString targetNodeId}の入力${toString targetSlot}がリンクを参照していません"
          ++ lib.optional (
            sourceOutput != null && !(acceptsType sourceOutput.type linkType)
          ) "  リンク${toString linkId}の型${linkType}が接続元の出力型${sourceOutput.type}と一致しません"
          ++ lib.optional (
            targetInput != null && !(acceptsType targetInput.type linkType)
          ) "  リンク${toString linkId}の型${linkType}が接続先の入力型${targetInput.type}と一致しません"
        ) workflow.links;
      in
      nodeReferenceErrors ++ linkEndpointErrors;
  };

  # 実装のテスト。全ての表明を通ると`true`になる。
  tests = {
    link =
      let
        link = self;
        validWorkflow = {
          nodes = [
            {
              id = 1;
              inputs = [ ];
              outputs = [
                {
                  type = "TEST";
                  links = [ 1 ];
                }
              ];
            }
            {
              id = 2;
              inputs = [
                {
                  type = "TEST";
                  link = 1;
                }
              ];
              outputs = [ ];
            }
          ];
          links = [
            [
              1
              1
              0
              2
              0
              "TEST"
            ]
          ];
        };
        brokenWorkflow = validWorkflow // {
          nodes = map (
            node:
            if node.id == 2 then
              node
              // {
                inputs = [
                  {
                    type = "TEST";
                    link = 2;
                  }
                ];
              }
            else
              node
          ) validWorkflow.nodes;
        };
        invalidSlotWorkflow = validWorkflow // {
          links = [
            [
              1
              1
              1
              2
              0
              "TEST"
            ]
          ];
        };
        invalidTypeWorkflow = validWorkflow // {
          links = [
            [
              1
              1
              0
              2
              0
              "OTHER"
            ]
          ];
        };
        # スロットの型をtypeへ差し替えたワークフローを作る。
        withInputType = type: {
          inherit (validWorkflow) links;
          nodes = map (
            node:
            if node.id == 2 then
              node
              // {
                inputs = [
                  {
                    inherit type;
                    link = 1;
                  }
                ];
              }
            else
              node
          ) validWorkflow.nodes;
        };
        # ワイルドカード型のスロットはどの型のリンクも受け入れる。
        wildcardWorkflow = withInputType "*";
        # カンマ区切りの複数型のスロットは列挙された型のリンクだけ受け入れる。
        multiTypeWorkflow = withInputType "TEST,OTHER";
        multiTypeMismatchWorkflow = withInputType "OTHER,ANOTHER";
        # 存在しないノードを接続先に指すリンク。
        missingNodeWorkflow = validWorkflow // {
          links = [
            [
              1
              1
              0
              3
              0
              "TEST"
            ]
          ];
        };
      in
      assert lib.assertMsg (link.invalidReferences validWorkflow == [ ]) "正常なワークフローを拒否しました";
      assert lib.assertMsg (link.invalidReferences brokenWorkflow != [ ]) "壊れたワークフローを検出できませんでした";
      assert lib.assertMsg (link.invalidReferences invalidSlotWorkflow != [ ]) "範囲外のスロットを検出できませんでした";
      assert lib.assertMsg (link.invalidReferences invalidTypeWorkflow != [ ]) "一致しないリンク型を検出できませんでした";
      assert lib.assertMsg (link.invalidReferences wildcardWorkflow == [ ]) "ワイルドカード型のスロットを拒否しました";
      assert lib.assertMsg (link.invalidReferences multiTypeWorkflow == [ ]) "複数型のスロットへの一致する型のリンクを拒否しました";
      assert lib.assertMsg (
        link.invalidReferences multiTypeMismatchWorkflow != [ ]
      ) "複数型のスロットのどの型とも一致しないリンクを検出できませんでした";
      assert lib.assertMsg (
        link.invalidReferences missingNodeWorkflow != [ ]
      ) "存在しないノードを指すリンクを検出できませんでした";
      true;
  };
in
assert lib.all lib.id (lib.attrValues tests);
self
