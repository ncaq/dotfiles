/**
  convertSafetensorsFp16: safetensorsのF32テンソルをF16へ変換したderivationを返す関数。

  型: { pkgs } -> Derivation -> Derivation

  引数:
    src - 変換元のsafetensorsファイルを出力するderivation(fetchurlなど)

  動作:
    1. `safetensors-fp16 convert`でsrcを読み、F32テンソルだけをF16へ変換して`$out`へ直接書く
    2. `safetensors-fp16 verify`で`$out`を読み直し、srcと全要素を突き合わせて検証する

  戻り値:
    変換済みのsafetensorsファイルそのものを`$out`とするderivation。
    `linkFarm`のpathへそのまま渡せる。

  なぜ必要か:
    ComfyUIの計算dtypeはfp16で確定しているが、
    CPU側の重みはmmapしたファイル上のdtypeのまま保持されてキャストされない。
    そのためホストが抱えるページキャッシュの量はファイル上のdtypeで決まり、
    fp32のままだとfp16の倍になる。
    14.29Bパラメータのモデルはfp32だとhigh/lowの2つで106.4GiBになり、
    物理メモリを超えてホストが応答しなくなる。
    fp32からfp16への丸めはIEEE 754のround-to-nearest-evenで、
    ComfyUIがランタイムで行うキャストとビット単位で一致するため生成結果は変わらない。

  なぜfetchurlのpostFetchで変換しないか:
    fetchurlはfixed-output derivationなので、
    postFetchを足すとhashが変換後の値になり、
    upstreamが配布しているファイルとの対応が追えなくなる。
    独立したderivationで包めばhashは原本のまま維持でき、
    変換ロジックを変えてもhashの手動更新が要らない。

  なぜ`$out`へ直接書くか:
    `$out`はサンドボックス内でも実際のstoreパスにbind mountされるため、
    一時ディレクトリを経由せずに書ける。
    数十GBを一時領域へステージしてから移すのは現実的ではない。
    変換か検証が失敗すればNixが`$out`ごと破棄するので、
    不完全な出力がstoreへ残ることはなく、
    検証してから配置するのと同じ保証が得られる。
*/
{ pkgs }:
let
  safetensorsFp16 = pkgs.callPackage ../pkgs/safetensors-fp16 { };
in
src:
let
  # storeパスを見ただけで変換済みだと分かるようにする。
  # ComfyUIから見えるファイル名はlinkFarmがmodel.nixの属性名で決めるので、
  # ここでの名前は配置されるファイル名には影響しない。
  baseName = builtins.baseNameOf (src.name or src);
  name = "${pkgs.lib.removeSuffix ".safetensors" baseName}-fp16.safetensors";
in
pkgs.runCommand name
  {
    nativeBuildInputs = [ safetensorsFp16 ];
    # 変換元を辿れるようにしておく。
    passthru.src = src;
  }
  ''
    safetensors-fp16 convert ${src} $out
    safetensors-fp16 verify ${src} $out
  ''
