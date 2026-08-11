/**
  Ollamaコンテナの各モジュールが共有する値を宣言するオプション。

  同じパスやフラグをモジュールごとにリテラルで書くと、
  片方だけ変更しても評価は成功して実機で壊れるまで気付けない。
  永続データ領域のパスはホストとコンテナの双方から参照されるため特に危ない。
*/
{ lib, config, ... }:
{
  options.local.ollama = {
    enableCuda = lib.mkOption {
      type = lib.types.bool;
      default = config.hardware.nvidia.enabled;
      defaultText = lib.literalExpression "config.hardware.nvidia.enabled";
      description = ''
        NVIDIAのGPUで推論するかどうか。
        falseならCPU向けのパッケージを使い、GPUのデバイスもコンテナへ渡さない。
        GPUを積んだホストを増やしてもここを編集しなくて済むように、
        NVIDIAのドライバを使うかどうかから導く。
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/ollama";
      description = ''
        モデルと署名鍵を置くOllamaの永続データ領域。
        ホストからコンテナへidmap bindするので両側で同じパスになる。
      '';
    };

    generalModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        ハードウェアの限界の範囲で汎用的に使えるモデル。
        用途を絞らない既定の選択肢で、速度にも品質にも極端に寄せない。
      '';
    };

    flashModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = ''
        回答の質よりも即答性を優先したモデル。
        短い質問や補完のように、待たされること自体が使い勝手を損なう用途に使う。
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = config.local.ollama.generalModels ++ config.local.ollama.flashModels;
      defaultText = lib.literalExpression "config.local.ollama.generalModels ++ config.local.ollama.flashModels";
      description = "Ollama registryからpullするモデル。";
    };

    freedomModels = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "GGUFから`ollama create`で登録する表現自由度重視モデル。";
    };
  };
}
