# denoiseの強さがサンプラーの選択とステップ数へ変換されることを検証する。
{ lib }:
let
  builder = import ../../../../nixos/host/bullet/comfyui/workflow/lib/builder.nix { inherit lib; };

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
true
