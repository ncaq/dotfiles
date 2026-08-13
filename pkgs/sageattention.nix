{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  torch,
  triton,
  ninja,
  stdenv,
  cudaCapabilities ? torch.cudaCapabilities,
}:
let
  # CUDAパッケージセットは引数で受け取らずtorchが公開するものを必ず使う。
  # 引数にするとcallPackageがスコープの`cudaPackages`を先に埋めてしまい、
  # nixpkgs既定のCUDAとtorch wheelのCUDAがずれると、
  # PyTorchのcpp_extensionがバージョン不一致でビルドを止める。
  inherit (torch) cudaPackages;
  cudaNvcc = cudaPackages.cuda_nvcc;
in
buildPythonPackage rec {
  pname = "sageattention";
  version = "2.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "thu-ml";
    repo = "SageAttention";
    tag = "v${version}";
    hash = "sha256-luHu7BkOLRg1LfwNvj3ieeaRSYHNYciMK56MCzkUQd4=";
  };

  build-system = [ setuptools ];

  buildInputs = [
    cudaPackages.cuda_cudart
    cudaPackages.cuda_cccl
    cudaPackages.libcublas
    cudaPackages.libcusolver
    cudaPackages.libcusparse
    stdenv.cc.cc.lib
  ];

  nativeBuildInputs = [
    cudaNvcc
    ninja
  ];

  # ninjaをnativeBuildInputsに追加すると、
  # setup hookがPythonのpypaBuildPhaseをninjaBuildPhaseへ置き換え、
  # build.ninjaがまだないソース直下でninjaを実行してしまう。
  # この置換だけを防ぎ、
  # pypaBuildPhase内のPyTorch BuildExtensionからninjaを使う。
  dontUseNinjaBuild = true;

  dependencies = [
    torch
    triton
  ];

  CUDA_HOME = cudaNvcc;
  TORCH_CUDA_ARCH_LIST = lib.concatStringsSep ";" cudaCapabilities;

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'setuptools>=62,<75' 'setuptools>=62' \
      --replace-fail 'wheel>=0.38,<0.44' 'wheel>=0.38' \
      --replace-fail 'packaging>=21,<24' 'packaging>=21'
  '';

  preBuild = ''
    export CPATH="${cudaPackages.cuda_cudart}/include:${cudaPackages.cuda_cccl}/include:${lib.getDev cudaPackages.libcublas}/include:${lib.getDev cudaPackages.libcusolver}/include:${lib.getDev cudaPackages.libcusparse}/include''${CPATH:+:$CPATH}"
    export MAX_JOBS="$NIX_BUILD_CORES"
  '';

  pythonImportsCheck = [ "sageattention" ];

  meta = {
    description = "Accurate and efficient plug-and-play low-bit attention";
    homepage = "https://github.com/thu-ml/SageAttention";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
