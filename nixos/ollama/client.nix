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
  contextLength = config.local.ollama.contextLength;
  ollama-client = pkgs.writeShellApplication {
    name = "ollama";
    runtimeEnv.OLLAMA_HOST = "127.0.0.1:${toString ollama.port}";
    # `ollama launch claude`がClaude Codeへ渡さない値をここで補う。
    # ollamaはクラウドのモデルを選んだ時しかこれらを設定しないため、
    # ローカルのモデルではClaude Codeが自分の既定値で動いてしまう。
    #
    # `CLAUDE_CODE_AUTO_COMPACT_WINDOW`は自動圧縮を始めるcontextの大きさ。
    # Claude Codeの既定はクラウドのモデルに合わせた200000で、
    # このホストのOllamaが扱う長さより大きい。
    # 大きいまま放置すると、
    # Claude Codeがまだ余裕があると判断している間にプロンプトが上限を超え、
    # Ollamaが黙って先頭を切り捨てる。
    # エラーにならないので、会話の前半だけを忘れたような壊れ方をする。
    #
    # `CLAUDE_CODE_MAX_OUTPUT_TOKENS`は1回の応答の上限。
    # ollamaのAnthropic互換アダプタはこれを`num_predict`へそのまま渡すので、
    # モデルの生成長の上限になる。
    # Claude Codeがモデル名から上限を引けない場合の既定は32000で、
    # 思考を出力するモデルではそこへ頻繁に到達して応答が途中で切れる。
    # contextの半分までは1回の応答に使えることにして、
    # 残りの半分を会話の履歴に残す。
    # Claude Codeはモデル名を引けない場合128000を上限に丸めるため、
    # CUDAのホストの65536はそのまま通る。
    #
    # どちらも呼び出し側が既に指定していればそちらを優先する。
    # 値を変えて試す時にこのラッパーを組み直さずに済ませるためである。
    text = ''
      : "''${CLAUDE_CODE_AUTO_COMPACT_WINDOW:=${toString contextLength}}"
      : "''${CLAUDE_CODE_MAX_OUTPUT_TOKENS:=${toString (contextLength / 2)}}"
      export CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_MAX_OUTPUT_TOKENS

      exec ${lib.getExe ollama.package} "$@"
    '';
  };
in
{
  environment.systemPackages = [ ollama-client ];
}
