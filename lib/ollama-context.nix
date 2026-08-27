/**
  Ollamaのcontextの長さと、その配分。

  型: { length = { cuda = Int; cpu = Int; }; budget = Int -> { context, output, history }; }

  `length`はアクセラレータごとの既定のcontextの長さ。
  `nixos/ollama/container.nix`が`OLLAMA_CONTEXT_LENGTH`へ設定する値で、
  この大きさにした根拠の実測はそちらのコメントにある。
  NixOSモジュールからは`local.ollama.contextLength`を参照すること。

  `budget`はその長さを1回の応答と会話の履歴へ配分する。
  llama.cppのcontextはプロンプトと生成したトークンの両方を含むため、
  ハーネスへ伝える「会話を圧縮し始める大きさ」と「1回の応答の上限」は、
  足してcontextに収まっていなければならない。
  片方をcontextそのものにしてしまうと、
  長い会話で長い応答を生成した瞬間に合計が溢れる。

  比率の1/4はCUDAのホストを基準に選んだ。
  `length.cuda`の131072に対して`output`が32768になり、
  Claude Codeが未知のモデルに使う既定の32000をわずかに上回る。
  思考を出力するモデルでも1回の応答が収まる大きさとして、
  既定を下回らせない範囲で最も履歴へ回せる比率である。

  CPUのホストではこの説明は成り立たない。
  `length.cpu`の32768に対して`output`は8192で、
  既定の32000を大きく下回る。
  これは意図した結果である。
  contextが小さいホストで応答へ既定分を確保すると履歴がほとんど残らず、
  会話が数往復で圧縮に入ってしまう。
  1回の応答の長さより会話の長さを優先する。
  そもそもCPU推論は毎秒20トークン程度なので、
  8192トークンでも書き切るのに数分かかる。

  home-managerの設定もこれらを必要とするため実体をここへ置く。
  home-managerからNixOSの`config`を引けない理由は、
  `lib/ollama-model-names.nix`の先頭に書いてある。
*/
{
  length = {
    cuda = 131072;
    cpu = 32768;
  };

  budget =
    contextLength:
    let
      # 1回の応答に使ってよい上限。
      output = contextLength / 4;
    in
    {
      # モデルが一度に保持できるトークンの総数。
      context = contextLength;
      inherit output;
      # 会話の履歴に使ってよい上限。
      # 応答の分を引いてあるので、生成しきってもcontextに収まる。
      # この引き算で導くことが`output + history == context`の保証である。
      # 両方に比率を書くと、片方だけ直した時に合計が溢れる。
      history = contextLength - output;
    };
}
