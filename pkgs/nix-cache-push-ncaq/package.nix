# sopsで暗号化されたシークレットから認証トークンを復号して、
# 自分のNixのバイナリキャッシュへ転送するラッパ。
#
# 以下のコマンドを提供する。
#
# - `cachix-push-ncaq`: `secrets/cachix.yaml`で`cachix push ncaq`する
# - `niks3-push-ncaq-public`: `secrets/niks3-public.yaml`で公開のniks3サーバに`niks3 push`する
# - `niks3-push-ncaq-private`: `secrets/niks3-private.yaml`でtailnet内のniks3サーバに`niks3 push`する
#
# 実行ファイルは`cachix-push-ncaq`と`niks3-push-ncaq`の2つで、
# 復号して転送するコマンドへ渡す部分を共有している。
# `niks3-push-ncaq-{public,private}`は、`niks3-push-ncaq`に既定の環境変数を足して包んだものである。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  cachix,
  niks3,
  sops,
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
      ./nix-cache-push-ncaq.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "nix-cache-push-ncaq" source { };
  # シークレットファイルはsops暗号化済みなので、
  # Nix storeに取り込んでビルド時に解決する。
  niks3Variants = {
    public = {
      secretsFile = ../../secrets/niks3-public.yaml;
      serverUrl = "https://niks3-public.ncaq.net/";
    };
    private = {
      secretsFile = ../../secrets/niks3-private.yaml;
      # overlayで全環境共通のパッケージとして生やすためNixOSの`config`は読めない。
      # `lib/tailnet.nix`の案内通りtailnet名を直接importして渡す。
      serverUrl = import ../../lib/niks3-private-tailscale-url.nix {
        inherit lib;
        tailnet = import ../../lib/tailnet.nix;
      };
    };
  };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      # 復号は`sops`に、転送は`cachix`に任せるので、PATHへ足して包む。
      wrapProgram "$out/bin/cachix-push-ncaq" \
        --prefix PATH : ${
          lib.makeBinPath [
            cachix
            sops
          ]
        }

      # 接続先を決めていない`niks3-push-ncaq`はPATHに出さない。
      mkdir -p "$out/libexec/nix-cache-push-ncaq"
      mv "$out/bin/niks3-push-ncaq" "$out/libexec/nix-cache-push-ncaq/niks3-push-ncaq"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (variant: cfg: ''
          makeWrapper "$out/libexec/nix-cache-push-ncaq/niks3-push-ncaq" \
            "$out/bin/niks3-push-ncaq-${variant}" \
            --set-default NIKS3_PUSH_NCAQ_SECRETS_FILE ${cfg.secretsFile} \
            --set-default NIKS3_PUSH_NCAQ_SERVER_URL ${lib.escapeShellArg cfg.serverUrl} \
            --prefix PATH : ${
              lib.makeBinPath [
                niks3
                sops
              ]
            }
        '') niks3Variants
      )}
    '';
  }))
  haskell.lib.compose.justStaticExecutables
]
