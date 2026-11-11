/**
  PFNの翻訳特化モデルPLaMo 3 Translateの重みを、
  Hugging Faceのrevとhashで固定して取得する。

  OllamaとCLIの両方が同じstoreのパスを使い、
  同じモデルを2か所に持たないようにするために共通化している。
  CLIにHugging Faceの`repo:quant`の形で渡すと、
  初回の実行時に最新のrevisionが検証なしでキャッシュへ取得されてしまう。

  型: { pkgs } -> { "31b-q4_k_m"; "8b-q4_k_m"; "2b-q4_k_m"; "0.8b-q4_0"; }
*/
{ pkgs }:
let
  fetchHuggingFace = import ./fetch-hugging-face.nix { inherit pkgs; };
in
{
  # revは`target_lang`を省略した時の挙動が日英の自動切り替えに変わった後のもの。
  "31b-q4_k_m" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-31b-GGUF";
    rev = "8b797b290907c84403877cb9d03150929f10b467";
    file = "plamo-3-translate-31b-Q4_K_M.gguf";
    hash = "sha256-R3iMPrcbgwkZqEVAIjgd6UOkPt+rZdrZ50KZcCjR+d8=";
  };
  "8b-q4_k_m" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-8b-GGUF";
    rev = "c67efa4eefdc14d3c97bf8f4f35ee58e2ecd2f42";
    file = "plamo-3-translate-8b-Q4_K_M.gguf";
    hash = "sha256-lOXT+RtCH3yJAN2qwnsRoZ90QUJslUu7JaL9YKFkAYc=";
  };
  # 公式CLIの既定のモデル。
  "2b-q4_k_m" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-2b-GGUF";
    rev = "4f672106b847200bfdc0f6af6c321cd94eba1aed";
    file = "plamo-3-translate-2b-Q4_K_M.gguf";
    hash = "sha256-H/2Qc6/McONczJQkKKorc9eqK56neb9QS3dTaeAnbBM=";
  };
  # 公式CLIが既定のモデルに付ける投機的デコーディングのドラフト。
  "0.8b-q4_0" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-0.8b-GGUF";
    rev = "1cf96ae02133958a20074bfdfab76517bb737d00";
    file = "plamo-3-translate-0.8b-Q4_0.gguf";
    hash = "sha256-M97tKCL3md5NFbsDvqGsQO+n1mPZI57lTMf2X1q5KRc=";
  };
}
