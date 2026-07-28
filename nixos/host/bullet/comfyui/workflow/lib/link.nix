{ lib }:
{
  invalidReferences =
    workflow:
    let
      findNode = id: lib.findFirst (node: node.id == id) null workflow.nodes;
      findLink = id: lib.findFirst (link: builtins.elemAt link 0 == id) null workflow.links;
      getSlot =
        slots: index:
        if 0 <= index && index < builtins.length slots then builtins.elemAt slots index else null;
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
      ) workflow.links;
    in
    nodeReferenceErrors ++ linkEndpointErrors;
}
