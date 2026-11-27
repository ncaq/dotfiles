# 書き捨てのスクリプトの言語の選び方

調査や一括編集などのために書き捨てのスクリプトを書く時の、
言語の選び方と書き方の方針です。

## 対象

インタプリタに処理を書いて渡すものは全て対象です。
`-c`やheredocで処理を渡さずに、
一度Writeツールでファイルに書いてから実行してください。

`rg`や`fd`などの既存のコマンドを組み合わせるだけのものは対象外です。

## 言語の選び方

以下を上から順に当てはめて、
最初に合った言語を使ってください。

- JSONに対する`jq`やデータベースに対するSQLのように、その作業のためのDSLがあるなら、そのDSL
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

ライブラリや処理系や外部のコマンドが要る時は、
以下を上から順に検討してください。
言語ごとの書き方は後の節にあります。

- 言語のスクリプトモードの依存関係の指定でスクリプトの中に書く。
  F# ScriptとHaskellのライブラリはこれで用意します。
- shebangの`nix shell`でnixpkgsから用意する。
  TypeScriptとPythonのライブラリ、
  処理系そのもの、
  外部のコマンドやシステムのライブラリはこれで用意します。
- リポジトリの依存関係として追加する。
  nixpkgsに無いものがどうしても必要な時は、
  書き捨てのスクリプトで済ませずにこれを検討してください。

TypeScriptとPythonでは、
npmやPyPIから直接ライブラリを取ってこないでください。
npmやPyPIのパッケージはインストールの時に任意のコードを実行できますが、
nixpkgsからパッケージを取ってくるだけならその機能はありません。

shebangの`nix shell`はパッケージを並べるだけなら1行で書けます。

```bash
#!/usr/bin/env -S nix shell nixpkgs#<要るパッケージ> nixpkgs#<処理系のパッケージ> --command <処理系のコマンド>
```

Pythonの`python3.withPackages`のように式を書く必要がある時は、
Pythonの節のように`#! nix`を複数行に書きます。

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
- `npm install`や`npx`でライブラリを取ってこないでください。
  npmのライブラリはnixpkgsにほとんど無いので、
  基本的にNodeの標準ライブラリだけで書くことになります。

## Python

```python
#!/usr/bin/env nix
#! nix shell --impure --expr ``(import (builtins.getFlake "nixpkgs") {}).python3.withPackages (ps: [ ps.httpx ])``
#! nix --command python3
import httpx

print(httpx.__version__)
```

- ライブラリはnixpkgsの`python3.withPackages`で束ねたPythonをshebangの`nix shell`で用意します。
  `nix shell nixpkgs#python3 nixpkgs#python3Packages.httpx`のように並べるだけでは、
  Pythonがライブラリを見つけられません。
- `#! nix`の行でスペースや`"`を含む式は、
  二重のバッククォートで囲まないとエラーになります。
- `pip install`や`uv`でPyPIからライブラリを取ってこないでください。

## シェルスクリプト

ほとんどの言語で書けない場合だけ使ってください。
