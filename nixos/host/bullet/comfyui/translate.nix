# 指示文を英語へ翻訳するPLaMo 3 Translateを、ComfyUIのコンテナの中で動かす。
# 呼ぶのは`pkgs/comfyui-ncaq-nodes`の`translate.py`。
#
# CPUで推論する。
# 翻訳が走る時はComfyUIが前回のモデルをVRAMに掴んでいることが多く、
# 同じGPUへ載せるとモデルを降ろして積み直す往復になる。
#
# 公式の`plamo-translate-cli`のサーバはMCPだけを話し、
# GGUFのチャットテンプレートを差し替えるので参照文脈を渡せない。
# そのため`llama-server`を直接動かす。
#
# コンテナの中に置くので寿命がコンテナに連動し、
# 宛先がループバックになってコンテナの出口を足さずに済む。
{
  lib,
  pkgs,
  pkgs-unstable,
  hardening,
  ...
}:
let
  plamoTranslateModel = import ../../../../lib/plamo-translate-model.nix { inherit pkgs; };
  # コンテナの中のループバックでしか待たないので、ホストのポートとは重ならない。
  port = 8189;
  arguments = [
    # bulletのCPUで動画の指示1件を訳すのに、2Bは0.86秒、8Bは1.51秒、31Bは5.83秒だった。
    # 訳文の差は小さく、8Bはタグの表記(`1girl`や`twintails`)を一番保った。
    "--model"
    plamoTranslateModel."8b-q4_k_m"
    # 公式CLIと同じドラフトの設定。約12トークン/秒が24から39トークン/秒になった。
    "--model-draft"
    plamoTranslateModel."0.8b-q4_0"
    "--spec-type"
    "draft-simple"
    "--spec-draft-n-max"
    "6"
    "--spec-draft-p-min"
    "0.6"
    "--host"
    "::1"
    "--port"
    (toString port)
    # 指示文と文脈を合わせても数百トークンに収まる。
    "--ctx-size"
    "4096"
    # 32以上にすると、入力が32トークンを超えたあたりからプロンプトの読み込みが約7秒かかる。
    # 31なら0.5秒以内に収まる。原因は確かめていない。
    "--ubatch-size"
    "31"
    # 物理コアの数。24でも変わらず、論理コアの数の32では0.4トークン/秒まで落ちた。
    "--threads"
    "16"
    "--parallel"
    "1"
    # GGUFに埋め込まれたテンプレートを使う。
    "--jinja"
    "--no-webui"
    # プロンプトのキャッシュは既定の有効のままにする。
    # 同じ文脈が続くと先頭の分が再利用され、文脈付きの10件が9.06秒から8.34秒になった。
    #
    # 公式CLIが渡すyarnの補正(`--yarn-beta-fast 31.738495 --yarn-beta-slow 1.0040927`)は渡さない。
    # llama.cppがPLaMo 3の`yarn_truncate`に対応していないための補正で、
    # ずれはトークン間の距離が伸びるほど大きくなる。
    # 補正の有無で9件を訳し比べると3件が変わったが、
    # 同義語の入れ替え(`changes`と`shifts`)と文末のピリオドの有無だけで、速度は変わらなかった。
  ];
in
{
  containers.comfyui.config = {
    systemd.services = {
      plamo-translate = {
        description = "PLaMo 3 Translate for ComfyUI prompts";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = hardening.network // {
          # stableのllama.cppはPLaMo 3に対応する前の版なのでunstableから取る。
          ExecStart = "${lib.getExe' pkgs-unstable.llama-cpp "llama-server"} ${lib.escapeShellArgs arguments}";
          DynamicUser = true;
          # 終了は全て異常なので再起動する。
          # 待っても直らない原因で繰り返さないよう、
          # `idle-free-memory.nix`と同じ指数バックオフで抑える。
          Restart = "always";
          RestartSec = "10s";
          RestartMaxDelaySec = "2h";
          RestartSteps = 10;
        };
      };
      # 依存関係では縛らない。
      # 翻訳サーバが落ちていれば、翻訳を呼んだノードがエラーになるだけで、
      # 翻訳を使わないワークフローは動き続ける。
      comfyui.environment.PLAMO_TRANSLATE_AUTHORITY = "[::1]:${toString port}";
    };
  };
}
