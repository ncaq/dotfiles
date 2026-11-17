# ComfyUIのカスタムノードを宣言的に導入する。
#
# `services.comfyui.customNodes`の属性名が、
# `custom_nodes/`配下のディレクトリ名になり、
# サービス起動時にNix storeからシンボリックリンクで配置される。
#
# comfyui-nixのPython環境には主要カスタムノードの依存
# (ultralytics, segment-anything, opencv4など)が同梱されているので、
# 大抵はソースを配置するだけでよい。
# 同梱されていない依存は`services.comfyui.extraPythonPackages`で追加する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  dataDir = config.containers.comfyui.config.services.comfyui.dataDir;
  # ComfyUI-Autocomplete-PlusがタグCSVをダウンロードする先。
  # Nix storeは読み取り専用なので可変領域に逃がす。
  autocompletePlusDataDir = "${dataDir}/autocomplete-plus";
  loraManager = pkgs.fetchFromGitHub {
    owner = "willmiao";
    repo = "ComfyUI-Lora-Manager";
    tag = "v1.2.0";
    hash = "sha256-xwAXjD5/Yxlmz5F1bKlw6iksiRf+SuNAoeeUnhohfM4=";
  };
  # ComfyUI-Lora-ManagerのPython依存をrequirements.txtから自動導出する。
  # 手書きのリストだとtag更新時に依存の増減へ追随し忘れて、
  # 実行時のImportErrorになるまで気付けない。
  # PyPI名をnixpkgsの属性名へ正規化して参照するので、
  # nixpkgsに存在しない依存が増えた場合は評価エラーで検出される。
  # バージョン制約は無視してnixpkgsのバージョンをそのまま使う。
  loraManagerPythonPackages =
    pythonPkgs:
    lib.pipe (builtins.readFile "${loraManager}/requirements.txt") [
      (lib.splitString "\n")
      # 行頭のパッケージ名だけを取り出す。
      # コメント行と空行はマッチしないのでnullになる。
      (map (line: builtins.match "[[:space:]]*([A-Za-z0-9._-]+).*" line))
      (lib.filter (matched: matched != null))
      (map (matched: lib.toLower (builtins.replaceStrings [ "_" "." ] [ "-" "-" ] (lib.head matched))))
      # requirements.txt内の並び替えだけで環境が再ビルドされないように順序を正規化する。
      (lib.sort lib.lessThan)
      (map (name: pythonPkgs.${name}))
    ];
in
{
  containers.comfyui.config.services.comfyui = {
    extraPythonPackages =
      pythonPkgs: [ pythonPkgs.rotary-embedding-torch ] ++ loraManagerPythonPackages pythonPkgs;
    # FaceDetailerなどディテール修復ノード群のImpact Pack(ADetailer相当)は、
    # comfyui-nixが同梱して配置するものを使うので、ここでは宣言しない。
    # ランチャーはExecStartで同梱ノードを`ln -sfn`するため、
    # 同梱ノードと同じ名前を`customNodes`に書いても同梱版で上書きされる。
    customNodes = {
      "ComfyUI-Ncaq-Nodes" = pkgs.comfyui-ncaq-nodes;
      # Civitaiからの取得、プレビュー、トリガーワード、レシピを一元管理する。
      # Civitaiにはpickle形式(.pt/.ckpt)のモデルもあり読み込み時の任意コード実行が懸念されるが、
      # ComfyUI本体は非safetensorsも`torch.load(weights_only=True)`固定で読むことと、
      # そもそも外部取得物の実行を想定したコンテナ隔離があることから受容する。
      "ComfyUI-Lora-Manager" = loraManager;
      # 複数フレームを同時に参照して時間的一貫性を保つ動画超解像。
      # RTX 5090では7B FP16モデルをBlockSwapとVAE tiling付きで使う。
      # 依存はextraPythonPackagesからComfyUI本体と同じCUDA版torchを使う。
      # 自作ノードの`seedvr2_streaming.py`が、
      # このディレクトリ名を辿って同梱のCLIを起動する。
      "ComfyUI-SeedVR2_VideoUpscaler" = pkgs.applyPatches {
        src = pkgs.fetchFromGitHub {
          owner = "numz";
          repo = "ComfyUI-SeedVR2_VideoUpscaler";
          rev = "4490bd1f482e026674543386bb2a4d176da245b9";
          hash = "sha256-6nsqFflLw9vYH/du35ET46fdAm1NMjjTe2bA8JmaBE4=";
        };
        patches = [ ./seedvr2-lossless.patch ];
        # GNU patchの既定はfuzz 2とオフセット探索で文脈のずれを黙って許容する。
        # 上流のrev更新でパッチの文脈が一致しなくなった時に、
        # 意味の違う位置へ適用されるより確実にビルド失敗させたい。
        patchFlags = [
          "-p1"
          "-F0"
        ];
      };
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
