/**
  Ollamaコンテナの各モジュールが共有する値を宣言するオプション。

  同じパスやフラグをモジュールごとにリテラルで書くと、
  片方だけ変更しても評価は成功して実機で壊れるまで気付けない。
  永続データ領域のパスはホストとコンテナの双方から参照されるため特に危ない。
*/
{ lib, config, ... }:
let
  contextLength = (import ../../lib/ollama-context.nix).length;
  # そのアクセラレータで使うモデルを役割ごとに並べたもの。
  roleType = lib.types.submodule {
    options = {
      general = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          ハードウェアの限界の範囲で汎用的に使えるモデル。
          用途を絞らない既定の選択肢で、速度にも品質にも極端に寄せない。
        '';
      };

      freedom = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          表現の自由度を優先したモデル。
          規制の強いモデルが応答を拒否する種類の題材に使う。
          待っていられる速度で動かせないハードウェアでは空にする。
        '';
      };
    };
  };
in
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

    contextLength = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      default = if config.local.ollama.enableCuda then contextLength.cuda else contextLength.cpu;
      defaultText = lib.literalExpression ''
        if config.local.ollama.enableCuda then contextLength.cuda else contextLength.cpu
      '';
      description = ''
        Ollamaが既定で使うcontextの長さ。
        `container.nix`が`OLLAMA_CONTEXT_LENGTH`へ設定する。
        この大きさにした根拠の実測はそちらのコメントにある。

        クライアント側も同じ値を必要とする。
        接続先が実際に扱える長さを知らないハーネスは、
        それより長いプロンプトを組み立ててしまい、
        Ollamaが黙って先頭を切り捨てる形で壊れるためである。

        値そのものは`lib/ollama-context.nix`が持っている。
        home-managerの設定もこの値を必要とするためである。
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

    models = lib.mkOption {
      type = lib.types.submodule {
        options = {
          cuda = lib.mkOption {
            type = roleType;
            description = "NVIDIAのGPUで推論するホストのモデル。";
          };

          cpu = lib.mkOption {
            type = roleType;
            description = "CPUで推論するホストのモデル。";
          };
        };
      };
      readOnly = true;
      description = ''
        アクセラレータごとに、役割から実際のモデル名を引く表。

        `attrsOf`ではなく`submodule`にしてあるのは、
        `hostModels`の既定値も`blue-prompt.nix`もキーを決め打ちで引くためである。
        キーを打ち間違えても`attrsOf`では型検査を通ってしまい、
        属性が無いというエラーで初めて露見する。

        自ホストで動かすモデルは`hostModels`から引く。
        こちらを直接引くのは他のホストのOllamaを指す場合に限る。
        Open WebUIのようにtailnet越しに別のホストのOllamaを使う設定は、
        自分のハードウェアではなく接続先のハードウェアでモデルが決まるため、
        アクセラレータを名指しする必要がある。
      '';
    };

    hostModels = lib.mkOption {
      type = roleType;
      readOnly = true;
      default = config.local.ollama.models.${if config.local.ollama.enableCuda then "cuda" else "cpu"};
      defaultText = lib.literalExpression ''config.local.ollama.models.''${if config.local.ollama.enableCuda then "cuda" else "cpu"}'';
      description = ''
        このホストのハードウェアで実際に動かすモデル。
        役割からモデル名を引きたい設定は基本的にこれを使う。
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default =
        with config.local.ollama;
        lib.subtractLists (lib.attrNames ggufModels) (hostModels.general ++ hostModels.freedom);
      defaultText = lib.literalExpression ''
        lib.subtractLists (lib.attrNames ggufModels)
          (hostModels.general ++ hostModels.freedom)
      '';
      description = ''
        Ollama registryからpullするモデル。
        役割のリストに書いた名前のうち、
        `ggufModels`で自前に組み立てるものはpullできないので除く。
      '';
    };

    ggufModels = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            sources = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              description = ''
                1つのモデルを構成するGGUFのリスト。
                言語モデル本体に加えて、
                visionを持つモデルはclipの投影器が要ります。
                `model`と判定されるGGUFは1つでなければなりません。
              '';
            };
            parameters = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.bool
                  lib.types.str
                  lib.types.int
                  lib.types.float
                ]
              );
              default = { };
              description = ''
                Modelfileの`PARAMETER`に書く既定値。
                registryのモデルはこれを同梱しているが、
                GGUFから組み立てる場合は自分で指定しないとOllamaの既定値になる。

                `use_mmap`や`low_vram`のような真偽値を取るPARAMETERがあるためboolも受ける。

                属性集合なので同じキーを複数回書くPARAMETERは表現できない。
                停止文字列を複数指定したい場合など、
                `stop`を並べる必要が出たらこの型を見直す必要がある。
              '';
            };
          };
        }
      );
      readOnly = true;
      description = ''
        GGUFから`ollama create`で登録するモデル。
        registryに求める量子化のタグが無い場合や、
        registryに存在しないモデルを使う場合に用いる。
      '';
    };
  };
}
