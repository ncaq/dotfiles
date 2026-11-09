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
    rev = "8aa0d99cd886de5c7efb1d9418ce56562f54946a";
    file = "plamo-3-translate-31b-Q4_K_M.gguf";
    hash = "sha256-R3iMPrcbgwkZqEVAIjgd6UOkPt+rZdrZ50KZcCjR+d8=";
  };
  "8b-q4_k_m" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-8b-GGUF";
    rev = "fccc6b15efc7d615189fa5df6a1a02ecd2dbc18f";
    file = "plamo-3-translate-8b-Q4_K_M.gguf";
    hash = "sha256-lOXT+RtCH3yJAN2qwnsRoZ90QUJslUu7JaL9YKFkAYc=";
  };
  # 公式CLIの既定のモデル。
  "2b-q4_k_m" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-2b-GGUF";
    rev = "228a27cc0bb4f111219963848d50a3127c16ca73";
    file = "plamo-3-translate-2b-Q4_K_M.gguf";
    hash = "sha256-H/2Qc6/McONczJQkKKorc9eqK56neb9QS3dTaeAnbBM=";
  };
  # 公式CLIが既定のモデルに付ける投機的デコーディングのドラフト。
  "0.8b-q4_0" = fetchHuggingFace {
    owner = "pfnet";
    repo = "plamo-3-translate-0.8b-GGUF";
    rev = "e10c327b7a7ce84ffc427cb4b09360b781429fda";
    file = "plamo-3-translate-0.8b-Q4_0.gguf";
    hash = "sha256-M97tKCL3md5NFbsDvqGsQO+n1mPZI57lTMf2X1q5KRc=";
  };
}
