# ComfyUIのカスタムノードを宣言的に導入する。
#
# `services.comfyui.customNodes`の属性名が、
# `custom_nodes/`配下のディレクトリ名になり、
# サービス起動時にNix storeからシンボリックリンクで配置される。
#
# comfyui-nixのPython環境には主要カスタムノードの依存
# (ultralytics, segment-anything, opencv4など)が同梱されているので、
# ここではソースを配置するだけでよい。
{ config, pkgs, ... }:
let
  dataDir = config.containers.comfyui.config.services.comfyui.dataDir;
  # ComfyUI-Autocomplete-PlusがタグCSVをダウンロードする先。
  # Nix storeは読み取り専用なので可変領域に逃がす。
  autocompletePlusDataDir = "${dataDir}/autocomplete-plus";
in
{
  containers.comfyui.config = {
    services.comfyui.customNodes = {
      # FaceDetailerなどディテール修復ノード群。ADetailer相当。
      # comfyui-nixがパッケージ済みのものを使う。
      "ComfyUI-Impact-Pack" = pkgs.comfyui-custom-nodes.impact-pack;
      # Power Lora Loaderなどワークフロー整理のノード群。
      # comfyui-nixがパッケージ済みのものを使う。
      "rgthree-comfy" = pkgs.comfyui-custom-nodes.rgthree-comfy;
      # UltralyticsDetectorProvider(YOLOによる顔検出)を提供する。
      # FaceDetailerに検出器を渡すために必要。
      "ComfyUI-Impact-Subpack" = pkgs.fetchFromGitHub {
        owner = "ltdrdata";
        repo = "ComfyUI-Impact-Subpack";
        tag = "1.3.4";
        hash = "sha256-BHtfkaqCPf/YXfGbF/xyryjt+M8izkdoUAKNJLfyvqI=";
      };
      # danbooruタグのオートコンプリート。
      # 日本語からの検索とpost count表示に対応していて、
      # メジャーなタグかどうかを確認しながら入力できる。
      "ComfyUI-Autocomplete-Plus" = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "comfyui-autocomplete-plus";
        version = "1.11.0";
        src = pkgs.fetchFromGitHub {
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
        patches = [ ./autocomplete-plus-new-frontend.patch ];
        # タグCSVを起動時に自ディレクトリ配下へダウンロードする作りだが、
        # Nix storeは読み取り専用なので、書き込み先を可変領域に差し替える。
        postPatch = ''
          substituteInPlace modules/api.py modules/downloader.py \
            --replace-fail \
            'os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "data"))' \
            '"${autocompletePlusDataDir}/data"'
          substituteInPlace modules/downloader.py \
            --replace-fail \
            'os.path.normpath(os.path.join(os.path.dirname(__file__), "..", CSV_META_FILE_NAME))' \
            'os.path.join("${autocompletePlusDataDir}", CSV_META_FILE_NAME)'
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r . $out/
          runHook postInstall
        '';
        meta = {
          description = "Danbooru tag autocomplete with Japanese search support for ComfyUI";
          homepage = "https://github.com/newtextdoc1111/ComfyUI-Autocomplete-Plus";
          license = pkgs.lib.licenses.mit;
        };
      });
    };
  };
  systemd.tmpfiles.rules = [
    "d ${autocompletePlusDataDir} 0755 comfyui comfyui - -"
    "d ${autocompletePlusDataDir}/data 0755 comfyui comfyui - -"
  ];
}
