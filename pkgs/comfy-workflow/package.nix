# ComfyUIのワークフローを名前付きのオプションで投げるコマンド。
#
# ワークフローごとの`comfy-<名前>`ラッパーから呼ぶ。
# ラッパーは`passthru.mkCommand`で作る。
# `nixos/host/bullet/comfyui/workflow/cli.nix`が、宣言したワークフローの全てをそうしている。
# 中身は公式の`comfy-cli`を呼ぶので、PATHへ足して包む。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  writeShellScriptBin,
  formats,
  comfy-cli,
  himari-src,
}:
let
  packages = haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" himari-src { };
    }
  );
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./comfy-workflow.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "comfy-workflow" source { };
  comfyWorkflow = lib.pipe package [
    (haskell.lib.compose.overrideCabal (old: {
      buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
      postInstall = (old.postInstall or "") + ''
        wrapProgram "$out/bin/comfy-workflow" \
          --prefix PATH : ${lib.makeBinPath [ comfy-cli ]}
      '';
    }))
    haskell.lib.compose.justStaticExecutables
  ];
  jsonFormat = formats.json { };
  /**
    ワークフローを1つ、`comfy-<名前>`というコマンドにする。

    渡すのはAPI形式ではなくUI形式のワークフローそのものである。
    API形式は公式CLIが実行時に組み立てる。
    二重管理を作らないためで、
    UIで開くものとコマンドで投げるものが必ず同じ内容になる。

    - `name`: ワークフローの名前。コマンドの名前と、ヘルプに出る名前になる。
      出力の接頭辞はワークフロー自身の`filename_prefix`で決まるので、それと揃えておく
    - `workflow`: UI形式のワークフローの属性集合
    - `authority`: 既定の接続先。`[::1]:8188`のようなホストとポート
    - `outputDir`: 既定の出力先。利用者へ見せるパスに使う
  */
  mkCommand =
    {
      name,
      workflow,
      authority,
      outputDir,
    }:
    writeShellScriptBin "comfy-${name}" ''
      # 環境変数が既にあればそちらを優先する。
      # bullet以外から`COMFYUI_AUTHORITY=bullet:8188`で叩けるようにするため。
      export COMFYUI_AUTHORITY="''${COMFYUI_AUTHORITY:-${authority}}"
      export COMFYUI_OUTPUT_DIR="''${COMFYUI_OUTPUT_DIR:-${outputDir}}"
      # 名前を別に渡す。
      # storeのファイル名は頭にハッシュが付くので、
      # パスからはワークフローの名前を取れない。
      exec ${lib.getExe comfyWorkflow} ${name} ${jsonFormat.generate "${name}.json" workflow} "$@"
    '';
in
comfyWorkflow.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit mkCommand;
  };
})
