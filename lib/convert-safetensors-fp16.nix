/**
  convertSafetensorsFp16: safetensorsのF32テンソルをF16へ変換したderivationを返す関数。

  型: { pkgs } -> { src, hash } -> Derivation

  引数:
    src - 変換元のsafetensorsファイルを出力するderivation(fetchHuggingFaceなど)
    hash - 変換後のファイルのSRI形式sha256ハッシュ

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
    独立したderivationで包めばsrcのhashは原本のまま維持できる。

  なぜfixed-output derivationにするか:
    通常のderivationだと出力パスが変換ツールとその依存(Pythonやnumpy)の
    storeパスから決まるため、
    flake.lockの更新のたびに再ビルドが必要になる。
    変換の入力であるfp32の原本は数十GBあり、
    システムクロージャからは参照されないのでGCで消えていて、
    再ビルドのたびに再ダウンロードが走っていた。
    変換は決定的でビット単位で同じ出力が得られるので、
    変換後のhashで出力パスを固定すれば、
    変換ツールが変わっても出力が既にstoreかバイナリキャッシュにある限り再ビルドされず、
    原本は本当に変換が必要なときにだけ取得される。

    fixed-output derivationにはネットワークアクセスが許されるが、
    この変換はネットワークを使わないので実質的な差はない。

  hashの求め方:
    新しいモデルを追加するときは`hash = ""`で一度ビルドして、
    hash mismatchのエラーに出る実際の値を書き写す。
    変換元の取得と変換に時間がかかるので、
    既に変換済みのファイルが手元にあるなら`nix hash file --sri`で先に求めても良い。

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
{ src, hash }:
let
  # storeパスを見ただけで変換済みだと分かるようにする。
  # ComfyUIから見えるファイル名はlinkFarmがmodel.nixの属性名で決めるので、
  # ここでの名前は配置されるファイル名には影響しない。
  # ただしfixed-output derivationでは名前も出力パスに含まれるので、
  # 名前を変えると既存の出力が使えなくなり再変換が走る。
  baseName = baseNameOf (src.name or src);
  name = "${pkgs.lib.removeSuffix ".safetensors" baseName}-fp16.safetensors";
in
pkgs.runCommand name
  {
    nativeBuildInputs = [ safetensorsFp16 ];

    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = hash;

    # 変換元を辿れるようにしておく。
    passthru.src = src;
  }
  ''
    safetensors-fp16 convert ${src} $out
    safetensors-fp16 verify ${src} $out
  ''
