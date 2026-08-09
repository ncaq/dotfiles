/**
  Ollamaコンテナの各モジュールが共有する値を宣言するオプション。

  同じパスやフラグをモジュールごとにリテラルで書くと、
  片方だけ変更しても評価は成功して実機で壊れるまで気付けない。
  永続データ領域のパスはホストとコンテナの双方から参照されるため特に危ない。
*/
{ lib, hostName, ... }:
{
  options.local.ollama = {
    enableCuda = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = hostName == "bullet";
      description = ''
        NVIDIAのGPUで推論するかどうか。
        falseならCPU向けのパッケージを使い、GPUのデバイスもコンテナへ渡さない。
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

    openWebuiStateDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/open-webui";
      description = ''
        チャット履歴や設定を置くOpen WebUIの永続データ領域。
        ホストからコンテナへidmap bindするので両側で同じパスになる。
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Ollama registryからpullするモデル。";
    };

    freedomModels = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "GGUFから`ollama create`で登録する表現自由度重視モデル。";
    };
  };
}
