# ComfyUIのカスタムノードのComfyUI-Impact-Subpack。
#
# UltralyticsDetectorProvider(YOLOによる顔検出)を提供する。
# FaceDetailerに検出器を渡すために必要。
#
# ソースをそのまま配置するだけなので、取得したソースそのものをパッケージにする。
{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "ltdrdata";
  repo = "ComfyUI-Impact-Subpack";
  tag = "1.3.4";
  hash = "sha256-BHtfkaqCPf/YXfGbF/xyryjt+M8izkdoUAKNJLfyvqI=";
}
