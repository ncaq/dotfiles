# コンテナ内のOllamaへ接続するCLIをホストから利用可能にする。
#
# `ollama launch <ハーネス>`はここで作った環境をそのまま子プロセスへ渡すため、
# ハーネスへ伝えたい値もこのラッパーで用意する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ollama = config.containers.ollama.config.services.ollama;
  budget = (import ../../lib/ollama-context.nix).budget config.local.ollama.contextLength;
  ollama-client = pkgs.writeShellApplication {
    name = "ollama";
    runtimeEnv.OLLAMA_HOST = "127.0.0.1:${toString ollama.port}";
    # `ollama launch claude`がClaude Codeへ渡さない値をここで補う。
    # ollamaはクラウドのモデルを選んだ時しかこれらを設定しないため、
    # ローカルのモデルではClaude Codeが自分の既定値で動いてしまう。
    #
    # `CLAUDE_CODE_AUTO_COMPACT_WINDOW`は会話を圧縮し始める大きさ。
    # Claude Codeはcontextの使用量がこの値へ近付くと会話を要約する。
    # 既定はクラウドのモデルに合わせた200000で、
    # このホストのOllamaが扱う長さより大きい。
    # 大きいまま放置すると、
    # Claude Codeがまだ余裕があると判断している間にプロンプトが上限を超える。
    #
    # `CLAUDE_CODE_MAX_OUTPUT_TOKENS`は1回の応答の上限。
    # ollamaのAnthropic互換アダプタはこれを`num_predict`へそのまま渡すので、
    # モデルの生成長の上限になる。
    # Claude Codeがモデル名から上限を引けない場合の既定は32000で、
    # 思考を出力するモデルではそこへ頻繁に到達して応答が途中で切れる。
    #
    # 2つは足してcontextに収まる必要がある。
    # llama.cppのcontextはプロンプトと生成したトークンの両方を含むため、
    # 圧縮の閾値をcontextそのものにすると、
    # 長い会話で長い応答を生成した瞬間に合計が溢れる。
    # 配分は`lib/ollama-context.nix`が決めている。
    #
    # Claude Codeはモデル名を引けない場合、
    # 圧縮の閾値をモデルのcontextで、
    # 応答の上限を128000で丸める。
    # CUDAのホストの98304と32768はどちらもそのまま通る。
    #
    # どちらも呼び出し側が既に指定していればそちらを優先する。
    # 値を変えて試す時にこのラッパーを組み直さずに済ませるためである。
    text = ''
      : "''${CLAUDE_CODE_AUTO_COMPACT_WINDOW:=${toString budget.history}}"
      : "''${CLAUDE_CODE_MAX_OUTPUT_TOKENS:=${toString budget.output}}"
      export CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_MAX_OUTPUT_TOKENS

      exec ${lib.getExe ollama.package} "$@"
    '';
  };
in
{
  environment.systemPackages = [ ollama-client ];
}
