# 書き捨てのスクリプトの言語の選び方

調査や一括編集などのために書き捨てのスクリプトを書く時の、
言語の選び方と書き方の方針です。

## 対象

インタプリタに処理を書いて渡すものは全て対象です。
`-c`やheredocで処理を渡さずに、
一度Writeツールでファイルに書いてから実行してください。

`jq`や`rg`などの既存のコマンドを組み合わせるだけのものは対象外です。

## 言語の選び方

以下を上から順に当てはめて、
最初に合った言語を使ってください。

- その作業にきわめて向いた強力なライブラリがあり、それをスムーズに使えるなら、その言語
- 解析や編集の対象のソースコードの言語が分かっているなら、その言語
- 作業しているリポジトリのメインの言語が決まっているなら、その言語

リポジトリのメインの言語を選ぶのは、
必要なランタイムが既に揃っているはずだからです。
後で書き捨てではなくなった時に、
そのままリポジトリへ追加しやすいからでもあります。

決まった言語が明らかにスクリプトの実行に向いていない場合や、
どれにも当てはまらない場合は、
以下の汎用の候補を上から順に検討してください。
前の言語が使えない時だけ次の言語に進んでください。

- F# Script
- Haskell
- TypeScript
- Python
- シェルスクリプト

## 依存関係の補い方

言語のライブラリは、
各言語のスクリプトモードの依存関係の指定でスクリプトの中に書いてください。
書き方は後の言語ごとの節にあります。

処理系そのものが入っていない時や、
外部のコマンドやシステムのライブラリのように言語のパッケージマネージャから取れないものが要る時だけ、
shebangで`nix shell`を指定して補ってください。

```bash
#!/usr/bin/env -S nix shell nixpkgs#<要るパッケージ> nixpkgs#<処理系のパッケージ> --command <処理系のコマンド>
```

## F# Script

汎用の候補の第一です。
そこそこ堅牢で、
エコシステムもそこそこ充実しています。
JITコンパイルされるので最適化を後回しにでき、
スクリプトの実行に向いています。

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

- `dotnet fsi`で実行します。
  shebangに`#!/usr/bin/env -S dotnet fsi`を書けば、
  実行権限を付けて直接実行できます。
- ファイルの拡張子は必ず`.fsx`にしてください。
  他の拡張子だと`dotnet fsi`はスクリプトを実行せずに対話モードに入り、
  何もしないまま終了コード0で終わります。
- NuGetのパッケージは`#r "nuget: パッケージ名, バージョン"`で読み込みます。
  初回の実行時に自動で取得されます。
- コマンドライン引数は`fsi.CommandLineArgs`で取れます。
  先頭の要素はスクリプト自身のパスです。
- 失敗を呼び出し元へ伝えるには、
  `eprintfn`で標準エラー出力に書いてから`exit 1`で終わらせてください。

## Haskell

```haskell
#!/usr/bin/env cabal
{- cabal:
build-depends: base, aeson
-}
import Data.Aeson (encode)

main :: IO ()
main = print (encode [1 :: Int, 2, 3])
```

- cabalのスクリプトモードで実行します。
- 依存関係は`{- cabal: -}`のブロックに書きます。
- 初回の実行時は依存関係のビルドに時間がかかります。

## TypeScript

型検査をせず`node`で直接実行します。
JavaScriptを書くくらいなら、
そのような場合でもTypeScriptで書いてください。

- ファイルの拡張子は`.ts`にしてください。
- `node`は型を取り除いて実行するだけなので、
  `enum`や値を持つ`namespace`のように型を取り除くだけでは済まない構文は使わないでください。
  実行した時点でエラーになります。

## Python

```python
#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["httpx"]
# ///
import httpx

print(httpx.__version__)
```

- `uv run --script`で実行します。
- 依存関係はPEP 723のinline script metadataに書きます。
- `pip install`で環境にパッケージを入れないでください。

## シェルスクリプト

ほとんどの言語で書けない場合だけ使ってください。
