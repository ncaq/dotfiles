日本語で記述してください。

Conventional Commitsを使います。

# Conventional Commits 1.0.0

## 概要

Conventional Commitsの仕様はコミットメッセージのための軽量の規約です。
明示的なコミット履歴を作成するための簡単なルールを提供します。
この規則に従うことで自動化ツールの導入を簡単にします。
コミットメッセージで機能追加・修正・破壊的変更などを説明することで、
この規約は[SemVer](http://semver.org/lang/ja/)と協調動作します。

コミットメッセージは次のような形にする必要があります:

---

```markdown
<型>[任意 スコープ]: <タイトル>

[任意 本文]

[任意 フッター]
```

---

あなたのライブラリの利用者に意図を伝えるために、
コミットは以下の構造化された要素を持ちます。

### _型_

#### `fix`

`fix`を持つコミットはコードベースのバグにパッチを当てます。

これはSemantic Versioningにおける[`PATCH`](http://semver.org/#summary)に相当します。

#### `feat`

`feat`を持つコミットはコードベースに新しい機能を追加します。

これはSemantic Versioningにおける[`MINOR`](http://semver.org/#summary)に相当します。

#### `BREAKING CHANGE`

*フッター*に`BREAKING CHANGE:`が書かれているか、
型/スコープの直後に`!`が追加されているコミットはAPIの破壊的変更を導入します。

Semantic Versioningにおける[`MAJOR`](http://semver.org/#summary)に相当します。

`BREAKING CHANGE`は任意の*型*のコミットに含めることができます。

#### `fix`や`feat`以外の*型*

それ以外の*型*も許されています。

たとえば、
[Angularの規約](https://github.com/angular/angular/blob/22b96b9/CONTRIBUTING.md#-commit-message-guidelines)
が基になっている、
[@commitlint/config-conventional](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-conventional)
は、

- `build`
- `chore`
- `ci`
- `docs`
- `feat`
- `fix`
- `perf`
- `refactor`
- `revert`
- `style`
- `test`

を推奨しています。

[git trailer format](https://git-scm.com/docs/git-interpret-trailers)に似た規約に従って、
`BREAKING CHANGE: <タイトル>`以外の*フッター*が与えられるかもしれません。

追加の型たちはConventional Commitsの仕様で義務付けられているものではなく、
BREAKING CHANGE を含まない限り、
Semantic Versioning に対する暗黙的な効果を持ちません。

### _スコープ_

コミットの型には追加の文脈の情報として*スコープ*を追加することができます。
スコープは括弧で囲みます。
たとえば`feat(parser): add ability to parse arrays`のようになります。

## 例

### タイトルおよび破壊的変更のフッターを持つコミットメッセージ

```markdown
feat: allow provided config object to extend other configs

BREAKING CHANGE: `extends` key in config file is now used for extending other config files
```

### 破壊的変更を目立たせるために `!` を持つコミットメッセージ

```markdown
feat!: send an email to the customer when a product is shipped
```

### スコープおよび破壊的変更を目立たせるための `!` を持つコミットメッセージ

```markdown
feat(api)!: send an email to the customer when a product is shipped
```

### `!` と BREAKING CHANGE フッターの両方を持つコミットメッセージ

```markdown
feat!: drop support for Node 6

BREAKING CHANGE: use JavaScript features not available in Node 6.
```

### 本文を持たないコミットメッセージ

```markdown
docs: correct spelling of CHANGELOG
```

### スコープを持つコミットメッセージ

```markdown
feat(lang): add polish language
```

### 複数段落からなる本文と複数のフッターを持ったコミットメッセージ

```markdown
fix: prevent racing of requests

Introduce a request id and a reference to latest request. Dismiss
incoming responses other than from latest request.

Remove timeouts which were used to mitigate the racing issue but are
obsolete now.

ref #123
Reviewed-by: Z
```

## 仕様

### キーワード

この文書におけるキーワード、

- 「しなければならない(MUST)」
- 「してはならない(MUST NOT)」
- 「要求されている(REQUIRED)」
- 「することになる(SHALL)」
- 「することはない(SHALL NOT)」
- 「する必要がある(SHOULD)」
- 「しないほうがよい(SHOULD NOT)」
- 「推奨される(RECOMMENDED)」
- 「してもよい(MAY)」
- 「選択できる(OPTIONAL)」

は[RFC 2119](https://www.ietf.org/rfc/rfc2119.txt)で述べられているように解釈されるべきものです。

### ルール

- コミットは`feat`や`fix`などの型から始まり(MUST)、
  その後ろにはスコープ(OPTIONAL)と`!`(OPTIONAL)が続き、
  その後ろにコロンとスペース(REQUIRED)が続く。
- コミットがあなたのアプリケーションやライブラリに新しい機能を追加するとき、
  型 `feat` が使われなければならない(MUST)。
- コミットがあなたのアプリケーションのためのバグ修正を行うとき、
  型 `fix` が使われなければならない(MUST)。
- スコープを型の後ろに記述してもよい(MAY)。
  スコープは、
  コードベースのセクションを記述する括弧で囲まれた名詞にしなければならない(MUST)。
  例: `fix(parser):`。
- 型/スコープの後ろのコロンとスペースの直後にタイトルが続かなければならない(MUST)。
  タイトルはコード変更の短い要約である。
  例: `fix: array parsing issue when multiple spaces were contained in string`。
- 短いタイトルの後ろにより長いコミットの本文を追加してもよい(MAY)。
  これはコード変更に関する追加の情報を提供する。
  本文はタイトルの下の1行の空行から始めなければならない(MUST)。
- コミットの本文は自由な形式であり、
  改行で区切られた複数の段落で構成することができる(MAY)。
- ひとつ以上のフッターを、
  本文の下の1行の空行に続けて書くことができる(MAY)。
  それぞれのフッターは、
  ひとつの単語トークン、
  それに続く`:<space>`か`<space>#`によるセパレータ、
  そして文字列の値から構成されなければならない(MUST)。
  これは[git trailer convention](https://git-scm.com/docs/git-interpret-trailers)に触発されている。
- フッターのトークンは空白の代わりに`-`を使わなければならない(MUST)。
  例えば`Acked-by`とする。
  これは複数段落からなる本文からフッターを区別するのに役立つ。
  例外として`BREAKING CHANGE`があり、
  これをトークンとして使用することができる(MAY)。
- フッターの値にはスペースと改行を含めることができる(MAY)。
  そして次のフッターのトークンとセパレータの組が見つかった時、
  以前のフッターのパースは終了しなければならない(MUST)。
- 破壊的変更は、
  コミットの型/スコープの接頭辞か、
  フッターによって明示されなければならない(MUST)。
- 破壊的変更がフッターとして含まれる場合は、
  大文字の`BREAKING CHANGE`の後ろにコロンとスペース、
  そしてタイトルを続けなければならない(MUST)。
  例: `BREAKING CHANGE: environment variables now take precedence over config files`。
- 破壊的変更が型/スコープの接頭辞として含まれる場合は、
  `:` の直前に `!` を用いて明示されねばならない(MUST)。
  `!` が使用された場合には、
  フッターから `BREAKING CHANGE:`を省略してもよい(MAY)。
  その場合はコミットのタイトル部分で破壊的変更の内容を説明することになる(SHALL)。
- `feat`と`fix`以外の型を使うことができる(MAY)。
  例: `docs: update ref docs.`。
- Conventional Commitsを構成する情報の単位は、
  大文字のBREAKING CHANGEを除き、
  実装において大文字と小文字を区別してはならない(MUST NOT)。
- フッターのトークンにおいて`BREAKING-CHANGE`は`BREAKING CHANGE`と、
  同じトークンとして解釈されなければならない(MUST)。

## Conventional Commitsは`revert`コミットをどのように扱いますか?

コードをrevertするのは複雑な場合があります。
複数のコミットをrevertしますか?
機能をrevertするとき、
次のリリースはただのパッチでしょうか?

Conventional Commitsはrevertの振る舞いを定義するための明示的な努力をしません。
その代わりに、
revertを処理するためのロジックを、
型とフッターの柔軟性を利用して開発するようなツールの作者にこれを任せます。

我々のおすすめの方法としては、
ひとつは`revert`型とrevertされるコミットのSHAを参照するフッターを使うようにすることです。

```markdown
revert: let us never again speak of the noodle incident

ref 486f89c6d7b33bcff263f6131f8ecb4ec18fd376
ref 96c64808f64c353ecaf060da98712272cfce30b8
```

# 使用する*型*の説明

コミットメッセージの先頭には、
変更の種類を示す型を書きます。

型一覧の順序は基本はアルファベット順ですが、
`fix`と`feat`は重要な型なので先頭に置いています。
`chore`と`revert`は特殊な性質を持つので最後に置いています。

以下のいずれかを選んでください。

## fix

バグ修正です。
本来意図した動作と異なっていたコードを直した時に使います。
Semantic Versioningの`PATCH`に相当します。

例:

- 特定の入力で誤った計算結果を返していたのを修正
- 境界値でクラッシュしていたのを修正
- メモリリークを修正

仕様通りに動いていたものの挙動を変える場合は、
`fix`ではなく`feat`を使います。

バグ修正の副作用でユーザにとって破壊的な変更が発生する場合は、
`fix!`のように破壊的変更を付与します。

## feat

新しい機能の追加です。
利用者から見える振る舞いが増えた時に使います。
Semantic Versioningの`MINOR`に相当します。

例:

- 新しいコマンドラインオプションを追加
- APIに新しいエンドポイントを追加
- 設定ファイルに新しい項目を受け付けるようにした

利用者にとって破壊的な変更が発生する場合は、
`feat!`のように破壊的変更を付与します。

利用者から呼び出せない内部関数の追加などなら、
`feat`ではなく`refactor`が適切なことが多いです。

## build

ビルドシステムや外部依存性に影響する変更です。

例:

- 依存パッケージのアップデート
- ビルドスクリプトの修正
- 言語処理系のバージョン要件の変更
- Dockerfileの変更

以下のファイルの変更は基本的に`build`になります。

- `Cargo.toml`
- `Dockerfile`
- `cabal.project`
- `flake.nix`
- `package.json`

## ci

CI/CD設定の変更です。

例:

- GitHub Actionsのワークフロー修正
- リリース自動化スクリプトの修正
- カバレッジ計測の設定変更

対象のファイルやディレクトリとしては、

- `.github/actions/`
- `.github/workflows/`
- `.gitlab-ci.yml`
- `Jenkinsfile`

などの変更が該当します。

`build`との違いは、
CIが「自動化された検証やデプロイの仕組み」を扱うのに対して、
`build`は「ビルドそのものの定義」を扱う点です。

## docs

ドキュメントだけの変更です。
コードの動作には影響しません。

例:

- READMEへの追記や修正
- コメントの修正
- typo修正

コード本体の識別子のtypoがAPIに影響するならば、
`docs`ではなく`fix`や破壊的変更です。

## perf

外部の振る舞いは変えずに、
パフォーマンスを改善する変更です。
`refactor`の特殊ケースと考えても良いです。

例:

- 計算量の小さいアルゴリズムに置き換えた
- 無駄なメモリ確保を減らした
- キャッシュを導入した

## refactor

外部から見える振る舞いを変えずに、
内部のコードを書き直す変更です。
バグ修正でも機能追加でもありません。

例:

- 関数を分割して読みやすくした
- 重複コードを共通化した
- 内部のデータ構造を入れ替えたが、公開APIは同じ

パフォーマンス改善が主目的の場合は`perf`を使います。

## style

コードの意味に影響しない見た目の変更です。

- ホワイトスペースを増減させた
- セミコロンの有無を統一
- 使用する構文を変更した

など。

例:

- フォーマッタ(fourmolu, prettier, rustfmtなど)を適用
  - フォーマッタの設定を変更して再フォーマットした
- インデントの統一

ロジックを変えるなら`refactor`を使います。

## test

テストの追加や修正だけの変更です。
プロダクションコードには触りません。

例:

- 未テストだった関数にテストを追加
- 壊れていたテストを修正
- テストヘルパの整理
- テストツールの導入

テストと同時にプロダクションコードのバグを直したならば、
コミットを分けるか、
主たる変更に合わせて`fix`を選びます。

## chore

上記のどれにも当てはまらない雑多な変更です。

例:

- 自分自身のパッケージのバージョンを上げる
- 開発環境設定ファイルの更新

`chore`を乱用することは避けるべきです。
本当にどれにも当てはまらない変更にだけ使うべきです。

## revert

以前のコミットを取り消す変更です。
取り消したコミットのSHAをフッターに記載するのが慣例です。

例:

```markdown
revert: let us never again speak of the noodle incident

ref 7d3f32c62efb6bbb309ac70af854a1a79219ce83
```
