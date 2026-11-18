# ComfyUIのカスタムノードを宣言的に導入する。
#
# `services.comfyui.customNodes`の属性名が、
# `custom_nodes/`配下のディレクトリ名になり、
# サービス起動時にNix storeからシンボリックリンクで配置される。
#
# ノードそのものは`pkgs/comfyui-*`にあり、
# ここではどれをどのディレクトリ名で置くのかだけを決める。
#
# comfyui-nixのPython環境には主要カスタムノードの依存
# (ultralytics, segment-anything, opencv4など)が同梱されているので、
# 大抵はソースを配置するだけでよい。
# 同梱されていない依存は`services.comfyui.extraPythonPackages`で追加する。
{
  pkgs,
  config,
  ...
}:
let
  comfyui = config.containers.comfyui.config.services.comfyui;
  autocompletePlus = pkgs.comfyui-autocomplete-plus.override {
    dataDir = "${comfyui.dataDir}/autocomplete-plus";
    inherit (comfyui) user group;
  };
in
{
  containers.comfyui.config.services.comfyui = {
    extraPythonPackages =
      pythonPkgs:
      pkgs.comfyui-seedvr2-video-upscaler.pythonDependencies pythonPkgs
      ++ pkgs.comfyui-lora-manager.pythonDependencies pythonPkgs;
    # FaceDetailerなどディテール修復ノード群のImpact Pack(ADetailer相当)は、
    # comfyui-nixが同梱して配置するものを使うので、ここでは宣言しない。
    # ランチャはExecStartで同梱ノードを`ln -sfn`するため、
    # 同梱ノードと同じ名前を`customNodes`に書いても同梱版で上書きされる。
    customNodes = {
      "ComfyUI-Ncaq-Nodes" = pkgs.comfyui-ncaq-nodes;
      # Civitaiにはpickle形式(.pt/.ckpt)のモデルもあり読み込み時の任意コード実行が懸念されるが、
      # ComfyUI本体は非safetensorsも`torch.load(weights_only=True)`固定で読むことと、
      # そもそも外部取得物の実行を想定したコンテナ隔離があることから受容する。
      "ComfyUI-Lora-Manager" = pkgs.comfyui-lora-manager;
      # RTX 5090では7B FP16モデルをBlockSwapとVAE tiling付きで使う。
      # 自作ノードの`seedvr2_streaming.py`が、
      # このディレクトリ名を辿って同梱のCLIを起動する。
      "ComfyUI-SeedVR2_VideoUpscaler" = pkgs.comfyui-seedvr2-video-upscaler;
      "ComfyUI-Impact-Subpack" = pkgs.comfyui-impact-subpack;
      "ComfyUI-Autocomplete-Plus" = autocompletePlus;
    };
  };
  # ComfyUI-Autocomplete-PlusがタグCSVをダウンロードする先。
  systemd.tmpfiles.rules = autocompletePlus.tmpfilesRules;
}
