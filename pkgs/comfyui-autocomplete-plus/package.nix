# ComfyUIのカスタムノードのComfyUI-Autocomplete-Plus。
#
# danbooruタグのオートコンプリート。
# 日本語からの検索とpost count表示に対応していて、
# メジャーなタグかどうかを確認しながら入力できる。
{
  lib,
  stdenv,
  fetchFromGitHub,
  # タグCSVをダウンロードする先。
  # 起動時に自ディレクトリ配下へダウンロードする作りだが、
  # Nix storeは読み取り専用なので、書き込み先を可変領域に差し替える。
  # ディレクトリを作るtmpfilesのルールを`passthru.tmpfilesRules`として出すので、
  # 使う側は`systemd.tmpfiles.rules`へ渡す。
  dataDir ? "/var/lib/comfyui/autocomplete-plus",
  # ComfyUIを動かすユーザとグループ。`dataDir`の所有者にする。
  user ? "comfyui",
  group ? "comfyui",
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "comfyui-autocomplete-plus";
  version = "1.11.0";
  src = fetchFromGitHub {
    owner = "newtextdoc1111";
    repo = "ComfyUI-Autocomplete-Plus";
    tag = "v${finalAttrs.version}";
    hash = "sha256-MjhGd38G5Wz46t1AchTe/IqmTzVO43mlXPDHie5i3EE=";
  };
  # 新しいComfyUIフロントエンド(1.43以降)では、
  # keyupの時点でカーソル位置がリセットされていて候補が表示されない。
  # upstreamのissueコメントで提示されている修正パッチを適用する。
  # https://github.com/newtextdoc1111/ComfyUI-Autocomplete-Plus/issues/73#issuecomment-4761276962
  # 修正がリリースされたらこのパッチは削除する。
  #
  # なおパッチとは別に、
  # フロントエンド設定のVue DOMモード(Vueノード描画)が有効だと、
  # この拡張はテキスト欄にattachできず一切動作しないので無効にしておくこと。
  patches = [ ./new-frontend.patch ];
  postPatch = ''
    substituteInPlace modules/api.py modules/downloader.py \
      --replace-fail \
      'os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "data"))' \
      '"${dataDir}/data"'
    substituteInPlace modules/downloader.py \
      --replace-fail \
      'os.path.normpath(os.path.join(os.path.dirname(__file__), "..", CSV_META_FILE_NAME))' \
      'os.path.join("${dataDir}", CSV_META_FILE_NAME)'
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';
  passthru = {
    tmpfilesRules = [
      "d ${dataDir} 0755 ${user} ${group} - -"
      "d ${dataDir}/data 0755 ${user} ${group} - -"
    ];
  };
  meta = {
    description = "Danbooru tag autocomplete with Japanese search support for ComfyUI";
    homepage = "https://github.com/newtextdoc1111/ComfyUI-Autocomplete-Plus";
    license = lib.licenses.mit;
  };
})
