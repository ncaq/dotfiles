# For LLM Instructions

## 出力設定

日本語で応答してください。
しかしコードのコメントなどは元の言語のままにしてください。

全角記号より半角記号を優先して使ってください。
特に全角括弧は禁止。

## 利用環境

基本的にOSにはNixOSの最新安定版を使っています。
テキストエディタにはEmacsを使っています。

## 推奨しないコマンド

### 非推奨

* `cat`: 代わりにあなた自身がファイルを読み込んでください。
* `find`: 代わりに`fd`を使ってください。
* `gh api`: 代わりに`gh`の専用サブコマンドを使ってください。
* `grep`: 代わりに`ripgrep`を使ってください。

### 禁止

* `git commit`: コミットは人間が行います。
* `rm`: 代わりに`trash`を使ってください。

* `head`: 全部読んでください。
* `tail`: 全部読んでください。

## 命名規則

### 意味のない単語の使用禁止

以下の要素、

- ファイル名
- ディレクトリ名
- モジュール名
- 関数名
- 変数名

などに`common`や`util`のような意味のない単語を使うのは禁止します。
それらの単語は乱用されていて意味がなくなっており、見ても何の意味を持っているのか分からないから。

変数名に`result`のような意味のない名前を使うのは禁止です。
その変数名に何を保存しているのか意味のある名前を付けてください。
実際に`Result`型の関連処理を行っている場合などは仕方ないですが。

### 原形の単数の利用の推奨

モジュール名や型の名前は、原形の単数形式を使うことを推奨します。
むやみに複数形を使うのは禁止。

変数の場合でも複数形よりも、もっと性質を表す名前を使うことを推奨します。

### エラー処理時にエラーデータを使う

エラーのようなものをcatchやcaseで受け取って、
そのまま上流にエラーを伝播させるのではなく、
その場所でエラーを処理するときは、
エラーデータを適切に使ってください。

例えば出現する原因を修正するのは困難だけど、
エラーによって致命的な問題にならない場合は、
普通は警告ログなどを出力してそのまま続行します。
その時警告ログにはエラーデータの内容を含めて、
開発者や利用者が問題を把握しやすいようにしてください。

エラーデータを`_`とかに代入してそのまま捨ててしまうことは禁止です。

## コメント

トップレベルに存在する関数や型にはドキュメントコメントを書いて説明してください。

内部の動作など見れば普通わかるものはコメントを書かないでください。

## 動作確認

作業を正常に完了するときはビルドとテストを全て成功させてください。
警告もなるべく解消してください。
全て正常に出来た場合のみ正常に完了したと考えてください。

作業が完了出来なかった場合は失敗したと報告してください。

## テスト

### テストコードは変更しない

テストコードの変更は基本的に禁止。
テストは仕様を表すものであり、実装の正しさを検証するためのものです。

テストが失敗している場合は、実装側を修正してください。
テストコードを実装に合わせるのは禁止。

テストが誤っていると思ったら質問してください。
独自判断でテストを書き換えるのは禁止。

#### テストコードを変更しても良い例外

テストコードを変更して良い例外は以下のような場合です。

- テストを追加するタスクを依頼されている。
- テストを修正するタスクを依頼されている。
- テストコードに明らかな構文エラーがある。
- テスト仕様が矛盾している。
    - この場合は独自に判断するのではなく質問して確認してください。
- テストコードがテスト対象のAPIと互換性がなくなっている。
    - この場合は独自に判断するのではなく質問して確認してください。

### テストデータに依存した条件分岐は避ける

実装コードがテストで使用されている具体的なデータ値を特別扱いすることは基本的に禁止。
具体的なデータ値とは、例えば変数名やテーブル名などです。

データに依存した実装は以下のような問題を引き起こします。

- 脆弱なテスト: テストデータが変更されると実装が機能しなくなる。
- 隠れた仕様: 特定のデータ名に対する特別な処理が明示的な仕様ではなく暗黙的になる。
- 汎用性の欠如: 実際の運用環境では機能しない可能性がある。
