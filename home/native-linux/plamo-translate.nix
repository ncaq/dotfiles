# PLaMo Translateでローカル翻訳するCLI。
#
# 推論を任せる`llama-server`とモデルはホストのハードウェアに合わせて選ぶ。
# stableのllama.cppはPLaMo 3に対応する前の版なのでどれもunstableから取る。
{
  lib,
  pkgs,
  pkgs-unstable,
  osConfig ? null,
  ...
}:
let
  # 空文字列はどのホスト名とも一致しないので、
  # NixOSの外のhome-managerでは下の既定の設定になる。
  # `null`を属性名に使うと`or`へ届く前に型エラーになる。
  hostName = osConfig.networking.hostName or "";
  setting =
    {
      # RTX 5090で速度を優先するのでCUDA版にする。
      # Vulkan版でもNVIDIAのGPUで動くが、
      # 行列積のカーネルはCUDA版の方が最適化されている。
      # CUDA版はどのキャッシュにも無く手元でビルドすることになるので、
      # nvccに渡すアーキテクチャをこのGPUのsm_120だけに絞ってビルド時間を抑える。
      # VRAMに余裕があるので最も精度の高い31Bを使う。
      bullet = {
        llama-cpp = pkgs-unstable.llama-cpp-cuda.overrideAttrs (old: {
          cmakeFlags =
            lib.filter (flag: builtins.match ".*CMAKE_CUDA_ARCHITECTURES.*" flag == null) old.cmakeFlags
            ++ [ (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "120") ];
        });
        model = "pfnet/plamo-3-translate-31b-GGUF:Q4_K_M";
        # 上流が既定のモデルに付けているのと同じ0.8Bのドラフト。
        # bulletでの実測(英文93トークンを日本語の96トークンへ訳す)では、
        # CUDA版の31Bだけで72トークン/秒のところ、
        # このドラフトを足すと193トークン/秒になり、
        # 83個の提案のうち72個が受理された。
        # 同じ条件でVulkan版の31Bは64トークン/秒で、
        # プロンプトの処理もCUDA版の8割ほどだった。
        draftModel = "pfnet/plamo-3-translate-0.8b-GGUF:Q4_0";
      };
      # 内蔵のRadeon 740Mは4CUしかなく、
      # VRAMもメインメモリと共有なのでCPUと同じ帯域を取り合う。
      # 生成の速度は帯域で決まるのでGPUへ載せても大差は無いと見て、
      # キャッシュがありドライバの癖も無いCPU版を使う。
      # 実測はしていない。
      # 対話的に待てる速度を優先して上流の既定の2Bのままにする。
      # 既定のモデルだけは0.8Bのドラフトによる投機的デコーディングが自動で効く。
      creep = {
        inherit (pkgs-unstable) llama-cpp;
        model = null;
      };
      # CPUで推論するのでGPUのバックエンドは要らない。
      # Ollamaの翻訳モデルと同じく、
      # CPUでも待っていられる範囲で精度を取って8Bにする。
      seminar = {
        inherit (pkgs-unstable) llama-cpp;
        model = "pfnet/plamo-3-translate-8b-GGUF:Q4_K_M";
      };
    }
    .${hostName} or {
      # 知らないホストでは多くのGPUで動くVulkan版と上流の既定のモデルにする。
      llama-cpp = pkgs-unstable.llama-cpp-vulkan;
      model = null;
    };
  plamo-translate-cli = pkgs.callPackage ../../pkgs/plamo-translate-cli setting;
in
{
  home.packages = [ plamo-translate-cli ];
}
