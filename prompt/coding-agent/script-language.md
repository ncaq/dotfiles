# 書き捨てのスクリプトの言語の選び方

調査や一括編集などのために書き捨てのスクリプトを書く時は、
以下を上から順に当てはめて、
最初に合った言語を使ってください。
`jq`や`rg`などの既存のコマンドを組み合わせるだけのものは、
この方針の対象外です。
`-c`やheredocでインタプリタに処理を書いて渡すのではなく、
一度Writeツールでファイルに書いてから実行してください。

- その作業にきわめて向いた強力なライブラリがあり、それをスムーズに使えるなら、その言語
- 解析や編集の対象のソースコードの言語が分かっているなら、その言語
- 作業しているリポジトリのメインの言語が決まっているなら、その言語

リポジトリのメインの言語を選ぶのは、
必要なランタイムが既に揃っているはずだからです。
後で書き捨てではなくなった時に、
そのままリポジトリへ追加しやすいからでもあります。

ここまでで決まった言語が明らかにスクリプトの実行に向いていない場合や、
どれにも当てはまらない場合は、
汎用の選択として以降のセクションの言語を上から順に検討してください。
前のセクションの言語が使えない時だけ、
次のセクションの言語に進んでください。

言語のライブラリは、
各言語のスクリプトモードの依存関係の指定でスクリプトの中に書いてください。

処理系そのものが入っていない時や、
外部のコマンドやシステムのライブラリのように言語のパッケージマネージャから取れないものが要る時だけ、
shebangで`nix shell`を指定して補ってください。

```bash
#!/usr/bin/env -S nix shell nixpkgs#<要るパッケージ> nixpkgs#<処理系のパッケージ> --command <処理系のコマンド>
```

## F# Script

汎用の選択の第一候補です。
そこそこ堅牢で、
エコシステムもそこそこ充実しています。
JITコンパイルされるので最適化を後回しにでき、
スクリプトの実行に向いています。

`dotnet fsi`で実行します。

```fsharp
#!/usr/bin/env -S dotnet fsi
#r "nuget: FSharp.Data, 6.4.1"

open FSharp.Data
open FSharp.Data.JsonExtensions

// 先頭の要素はスクリプト自身のパスなので取り除きます。
let args = fsi.CommandLineArgs |> Array.tail

if args.Length = 0 then
    eprintfn "JSONのファイルを指定してください"
    exit 1

let json = JsonValue.Load args[0]
printfn "%d" (json?count.AsInteger())
```

- ファイルの拡張子は必ず`.fsx`にしてください。
  他の拡張子だと`dotnet fsi`はスクリプトを実行せずに対話モードに入り、
  何もしないまま終了コード0で終わります。
- shebangに`#!/usr/bin/env -S dotnet fsi`を書けば、
  実行権限を付けて直接実行できます。
- NuGetのパッケージは`#r "nuget: パッケージ名, バージョン"`で読み込みます。
  初回の実行時に自動で取得されます。
- コマンドライン引数は`fsi.CommandLineArgs`で取れます。
  先頭の要素はスクリプト自身のパスです。
- 失敗を呼び出し元へ伝えるには、
  `eprintfn`で標準エラー出力に書いてから`exit 1`で終わらせてください。

## Haskell

cabalのスクリプトモードで実行します。
依存関係は`{- cabal: -}`のブロックにスクリプトの中で書けます。

```haskell
#!/usr/bin/env cabal
{- cabal:
build-depends: base, aeson
-}
import Data.Aeson (encode)

main :: IO ()
main = print (encode [1 :: Int, 2, 3])
```

初回の実行時は依存関係のビルドに時間がかかります。

## TypeScript

JavaScriptを書くくらいなら、
型検査をせず`node`コマンドで直接実行するだけの場合でもTypeScriptで書いてください。

## Python

依存関係は`uv run --script`とPEP 723のinline script metadataでスクリプトの中に書いてください。
`pip install`で環境にパッケージを入れないでください。

```python
#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["httpx"]
# ///
import httpx

print(httpx.__version__)
```

## シェルスクリプト

ほとんどの言語で書けない場合だけ使ってください。
