# 書き捨てのスクリプトの言語の選び方

調査や一括編集などのために書き捨てのスクリプトを書く時は、
以下を上から順に当てはめて、
最初に合った言語を使ってください。

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

処理系や依存関係が入っていない時は、
各言語のスクリプトモードの依存関係の指定で補ってください。
それでも補えない場合は、
shebangで`nix shell`を指定して補ってください。

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

F# Scriptが使えない時の候補です。

依存関係の指定をスクリプトの中で完結させにくいので、
shebangの`nix shell`でパッケージ付きのGHCを用意してください。

```haskell
#!/usr/bin/env nix
#! nix shell --impure --expr ``(import (builtins.getFlake "nixpkgs") {}).haskellPackages.ghcWithPackages (ps: [ ps.aeson ])``
#! nix --command runghc
import Data.Aeson (encode)

main :: IO ()
main = print (encode [1 :: Int, 2, 3])
```

`#! nix`の行で`"`を使う式は、
二重のバッククォートで囲まないとエラーになります。

## TypeScript

F# ScriptもHaskellも使えない時の候補です。
汎用の選択としてはなるべく避けてください。

JavaScriptを書くくらいなら、
型検査をせず`node`コマンドで直接実行するだけの場合でもTypeScriptで書いてください。

## Python

TypeScriptも使えない時の候補です。
汎用の選択としてはなるべく避けてください。

## シェルスクリプト

ここまでのどの言語も使えない時の最後の手段です。
TypeScriptやPythonより優先しないでください。
