{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  torch,
  triton,
  ninja,
  stdenv,
  cudaPackages ? torch.cudaPackages,
  cudaCapabilities ? torch.cudaCapabilities,
}:
let
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
  '';

  pythonImportsCheck = [ "sageattention" ];

  meta = {
    description = "Accurate and efficient plug-and-play low-bit attention";
    homepage = "https://github.com/thu-ml/SageAttention";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
