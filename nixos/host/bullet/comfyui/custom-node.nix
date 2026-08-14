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
in
{
  containers.comfyui.config =
    { config, ... }:
    let
      comfyuiPython = config.services.comfyui.package.pythonRuntime.python;
      # Pythonソースをビルド時に構文検査するシェルコマンドを組み立てる。
      # 文法エラーがあってもコンテナ起動時のノード読み込み失敗まで気付けないため、
      # 自作ノードの配置とパッチ適用の両方でこれを通す。
      #
      # ast.parseは構文木さえ作れれば通してしまい、
      # パッチのインデント崩れで関数の外へ出たreturnやループ外のbreakを見逃す。
      # py_compileと同じcompile()まで通しつつ、
      # 書き込み不可のstoreの隣へバイトコードを出さないよう自前で呼ぶ。
      #
      # ソースはbytesで読む。
      # テキストモードだとロケール未設定のビルド環境ではASCII扱いになり、
      # 日本語コメントで構文と無関係な復号エラーになる。
      # bytesならcompile()がPEP 263に従いUTF-8として解釈する。
      checkPythonSyntax = path: ''
        ${comfyuiPython}/bin/python -c \
          'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' \
          ${path}
      '';
      # 自作カスタムノードのディレクトリを構文検査してから丸ごと配置する。
      #
      # `share_encode.py`のような複数のノードで共有するモジュールは、
      # 実体を`custom-node/`直下に置き、
      # 使う側のノードディレクトリには`../share_encode.py`へのsymlinkを置いている。
      # ディレクトリ構造がそのまま相対importの解決になるので、
      # ComfyUIが読む配置とpyrightが見る配置を別々に組み立てずに済む。
      # `cp -rL`でsymlinkを実体化して配置するため、
      # 読み込み側から見た`custom_nodes/`配下の見え方は実体を並べた場合と変わらない。
      writeCheckedNode =
        dirName:
        pkgs.runCommand "comfyui-${dirName}" { } ''
          cp -rL ${./custom-node}/${dirName} $out
          for source in $(find $out -name '*.py'); do
            ${checkPythonSyntax "\"$source\""}
          done
        '';
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
      services.comfyui = {
        extraPythonPackages =
          pythonPkgs: [ pythonPkgs.rotary-embedding-torch ] ++ loraManagerPythonPackages pythonPkgs;
        customNodes = {
          # FaceDetailerなどディテール修復ノード群。ADetailer相当。
          # comfyui-nixがパッケージ済みのものを使う。
          # Impact Packの顔cropは任意寸法になり、Cosmos系のAnimaではlatentが、
          # spatial patch sizeで割り切れずFaceDetailerが失敗する。
          # 上流で修正されたら補正パッチを削除する。
          # https://github.com/ltdrdata/ComfyUI-Impact-Pack/issues/1186
          "ComfyUI-Impact-Pack" = pkgs.comfyui-custom-nodes.impact-pack.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./impact-pack-anima-size.patch ];
            # 上流更新で文脈がずれた場合に別の関数へ黙って適用しないようfuzzを無効化する。
            # overrideAttrsで指定するため、上流パッケージにpatchesが追加された場合も同じフラグが適用される。
            patchFlags = [
              "-p1"
              "-F0"
            ];
            # パッチのインデント崩れをComfyUI起動前のビルド時に検出する。
            postPatch = (old.postPatch or "") + checkPythonSyntax "modules/impact/core.py";
          });
          # Power Lora Loaderなどワークフロー整理のノード群。
          # comfyui-nixがパッケージ済みのものを使う。
          "rgthree-comfy" = pkgs.comfyui-custom-nodes.rgthree-comfy;
          # Civitaiからの取得、プレビュー、トリガーワード、レシピを一元管理する。
          # Civitaiにはpickle形式(.pt/.ckpt)のモデルもあり読み込み時の任意コード実行が懸念されるが、
          # ComfyUI本体は非safetensorsも`torch.load(weights_only=True)`固定で読むことと、
          # そもそも外部取得物の実行を想定したコンテナ隔離があることから受容する。
          "ComfyUI-Lora-Manager" = loraManager;
          # 複数フレームを同時に参照して時間的一貫性を保つ動画超解像。
          # RTX 5090では7B FP16モデルをBlockSwapとVAE tiling付きで使う。
          # 依存はextraPythonPackagesからComfyUI本体と同じCUDA版torchを使う。
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
          # SeedVR2 CLIのチャンク処理をComfyUIから起動し、長尺動画をRAM上限付きで処理する。
          # 解像度の自動計算に使う、VIDEOから幅と高さを取り出す汎用ノードGetVideoSizeも同梱する。
          "ComfyUI-SeedVR2-Streaming" = writeCheckedNode "seedvr2-streaming";
          # UltralyticsDetectorProvider(YOLOによる顔検出)を提供する。
          # FaceDetailerに検出器を渡すために必要。
          "ComfyUI-Impact-Subpack" = pkgs.fetchFromGitHub {
            owner = "ltdrdata";
            repo = "ComfyUI-Impact-Subpack";
            tag = "1.3.4";
            hash = "sha256-BHtfkaqCPf/YXfGbF/xyryjt+M8izkdoUAKNJLfyvqI=";
          };
          # 指示文を英語へ翻訳する自作ノード。
          # Qwen-Image-Editなど指示文の公式サポートが英語と中国語のみのモデルに対して、
          # 日本語で指示を書けるようにする。
          # 依存はComfyUI環境に同梱済みのrequestsのみ。
          # customNodesの型はpackageなのでプレーンなパスは渡せず、
          # derivationに包んで渡す。
          "ComfyUI-Translate-Text" = writeCheckedNode "translate-text";
          # 画像を選ばないことも許可する自作LoadImage。
          # (none)のままなら出力がNoneになり、optional入力が未接続扱いになる。
          # WanFirstLastFrameToVideoのend_imageなど任意入力の有効・無効を、
          # バイパス操作なしで画像指定の有無だけで切り替えるために使う。
          "ComfyUI-Load-Image-Optional" = writeCheckedNode "load-image-optional";
          # Animaなどlatent寸法に制約があるモデル向けの自作ノード群。
          # 画像を指定した倍数へ中央cropするノードと、
          # EmptyLatentImageへ渡す幅と高さを指定した倍数へ切り下げるノードを提供する。
          "ComfyUI-Align-Image-Size" = writeCheckedNode "align-image-size";
          # 元fpsと音声を維持し、RGB48から10-bit SVT-AV1 losslessのWebMへ保存するノード。
          "ComfyUI-Save-SVT-AV1" = writeCheckedNode "save-svt-av1";
          # 複数行の指示からQwen編集画像を先に全て作り、
          # そのキーフレーム間をWan FLF2Vで順番に動画化する。
          # 各成果物を都度保存するため、長さに比例して画像テンソルをRAMへ蓄積しない。
          "ComfyUI-Anime-Video-Quick" = writeCheckedNode "anime-video-quick";
          # 本体のSaveImageが書き出したPNGを保存後に縮める自作ノード。
          # ノードは提供せず、保存処理を包む副作用だけを持つ。
          "ComfyUI-Optimize-Png" = writeCheckedNode "optimize-png";
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
    };
  systemd.tmpfiles.rules = [
    "d ${autocompletePlusDataDir} 0755 comfyui comfyui - -"
    "d ${autocompletePlusDataDir}/data 0755 comfyui comfyui - -"
  ];
}
