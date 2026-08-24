/**
  openWebuiUserSettingsMergeTest: `user-settings.nix`のマージのjqのフィルタを検査するderivation。

  型: { pkgs } -> derivation

  引数:
    pkgs - jqと`runCommand`を取るためのnixpkgs

  何を検査するか:
    利用者の設定のマージ処理は`user`表の自由形式JSONに対するjqのフィルタとして書かれていて、
    リポジトリの既存のテスト(`flake.nix`の`checks`にある`mkNixTest`系や
    `comfyui-custom-node-test`)のどれにも掛からない。
    フィルタの鍵名を書き間違えても、上流が`settings.ui`の形を変えても、
    APIは自由形式のJSONをそのまま受け入れるので、
    設定が効かなくなったことに気付く手段がこれまで実機の目視しかなかった。

    フィルタ自体は`user-settings-merge.jq`にあり、
    このderivationと同期のスクリプトの両方が同じファイルを読む。

    以下3ケースの合成結果を固定して検査する。

    - `current`が`null`(設定を一度も書いたことが無い利用者)
    - 既存の`ui`が宣言していない鍵を持つ場合(宣言していない鍵が保たれるか)
    - 合成結果を再び`current`として与えた場合(冪等性)

    どのケースも`system`は末尾に改行を付けて渡し、
    フィルタの`rtrimstr("\n")`が落とすことも一緒に検査する。
*/
{ pkgs }:
let
  inherit (pkgs) lib;

  # `./user-settings-merge.jq`は評価しているflakeの自己ソースの中のファイルなので、
  # パスのままシェルへ埋めても文字列にストアへのコンテキストが付かない。
  # `builtins.readFile`でここの評価時に中身を文字列として取り込んでしまえば、
  # 埋め込むのは只のjqのプログラム文字列になり、この問題を避けられる。
  # 派生の値ではなくソースツリー中のファイルを読むだけなので、IFDにもならない。
  mergeFilter = builtins.readFile ./user-settings-merge.jq;

  jq = lib.getExe pkgs.jq;

  # 1件のケースを検査するシェルの断片。
  # 実際の出力と期待値の両方を`--sort-keys`で正規化して比較し、
  # 一致しなければケース名と両方の値を添えて即座に失敗させる。
  check =
    name:
    {
      current,
      declared,
      system,
      expected,
    }:
    ''
      actual=$(
        ${jq} --null-input \
          --argjson current ${lib.escapeShellArg (builtins.toJSON current)} \
          --argjson declared ${lib.escapeShellArg (builtins.toJSON declared)} \
          --arg system ${lib.escapeShellArg system} \
          ${lib.escapeShellArg mergeFilter} |
          ${jq} --compact-output --sort-keys .
      )
      expected=$(${jq} --null-input --compact-output --sort-keys ${lib.escapeShellArg (builtins.toJSON expected)})
      if [ "$actual" != "$expected" ]; then
        echo "${name}: 期待した合成結果と一致しませんでした" >&2
        echo "${name}: 期待 $expected" >&2
        echo "${name}: 実際 $actual" >&2
        exit 1
      fi
    '';
in
pkgs.runCommand "open-webui-user-settings-merge-test" { } ''
  ${check "current-null" {
    current = null;
    declared = {
      ctrlEnterToSend = true;
    };
    system = "こんにちは\n";
    expected = {
      ctrlEnterToSend = true;
      system = "こんにちは";
    };
  }}
  ${check "current-existing" {
    current = {
      ui = {
        ctrlEnterToSend = false;
        models = [ "gpt-oss:120b" ];
      };
    };
    declared = {
      ctrlEnterToSend = true;
    };
    system = "こんにちは\n";
    expected = {
      ctrlEnterToSend = true;
      models = [ "gpt-oss:120b" ];
      system = "こんにちは";
    };
  }}
  ${check "idempotent" {
    current = {
      ui = {
        ctrlEnterToSend = true;
        models = [ "gpt-oss:120b" ];
        system = "こんにちは";
      };
    };
    declared = {
      ctrlEnterToSend = true;
    };
    system = "こんにちは\n";
    expected = {
      ctrlEnterToSend = true;
      models = [ "gpt-oss:120b" ];
      system = "こんにちは";
    };
  }}

  touch $out
''
