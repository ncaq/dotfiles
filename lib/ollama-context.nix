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

  `output`をcontextの1/4にしているのは、
  Claude Codeが未知のモデルに使う既定の32000を下回らせないためである。
  CUDAのホストの131072に対して32768になり、
  残りの98304を会話の履歴に使える。

  home-managerの設定もこれらを必要とするため実体をここへ置く。
  home-managerからNixOSの`config`を引けない理由は、
  `lib/ollama-model-names.nix`の先頭に書いてある。
*/
{
  length = {
    cuda = 131072;
    cpu = 32768;
  };

  budget = contextLength: {
    # モデルが一度に保持できるトークンの総数。
    context = contextLength;
    # 1回の応答に使ってよい上限。
    output = contextLength / 4;
    # 会話の履歴に使ってよい上限。
    # 応答の分を引いてあるので、生成しきってもcontextに収まる。
    history = contextLength - contextLength / 4;
  };
}
