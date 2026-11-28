/**
  `lib/`の定義を1つの属性集合にまとめたもの。

  型: { lib, inputs } -> AttrSet

  `flake.nix`が1回だけ組み立てて、`localLib`という名前で配る。
  使う側は相対パスで`import`せずに、引数で受け取って使う。

  - NixOSのモジュール: `specialArgs`(`nixos/mk-nixos-system.nix`)
  - home-managerのモジュール: `extraSpecialArgs`
    (`nixos/mk-nixos-system.nix`と`home/mk-linux-home-manager.nix`と`nix-on-droid/default.nix`)
  - `pkgs/`のパッケージ: `callPackage`が自動で渡す引数(`local-packages-overlay.nix`)
  - `*.test.nix`のテスト: `test/collect-nix-tests.nix`が渡す引数

  NixOS Testの中のマシンは別のモジュール評価なので、`localLib`は届かない。
  `nixos/core/caddy.test.nix`のように、
  テストが受け取った`localLib`から、
  マシンのモジュールが必要とする引数(`hardening`など)を`node.specialArgs`へ自分で渡す。

  ファイルごとに引数の形が違うので、ディレクトリを走査せずに明示的に並べる。
  ファイルを足したらここにも1行足す。
  `lib/`の中のファイル同士は相対パスで`import`する。
  `localLib`は`lib/`の外へ配るためのもの。

  # `lib/`に置くもの

  `lib/`はなるべく小さく保つ。
  置くのは以下のどれかに当てはまるものだけにする。

  - 引数を取って値を返す関数で、特定のモジュールの都合に依らないもの。
    `fetch-hugging-face.nix`や`parse-ipv6.nix`のように、性質がライブラリそのものであるもの
  - NixOSとhome-managerと`pkgs/`のように、複数の木から共有される定義。
    `tailnet.nix`のように、NixOSの`config`を読めない構成からも同じ値を引く必要があるもの
  - `import-dir-modules.nix`のように、`flake.nix`が構成を組み立てる土台になるもの

  当てはまらないものは、使う側の近くに置く。

  - 使う場所が1つのファイルに閉じていて短いものは、そのファイルに直接書く
  - 長いものや、複数のモジュールから等しく使われるものは、使う側のディレクトリに独立したファイルとして置く。
    置くだけで読み込まれるディレクトリではモジュールにして、
    `nixos/native-linux/seminar-cifs.nix`のように`_module.args`で渡すか、
    `nixos/core/cpu-target-kernel.nix`のように自分で設定する
  - パッケージと組になるモジュールや関数は、`pkgs/<名前>/`の隣に置く(`pkgs/README.md`)
  - ホストをまたいで共有する値は、`flake.nix`の`hostInfo`に書く

  # 引数

  - `lib`: nixpkgsの`lib`
  - `inputs`: flakeの`inputs`。`localPackagesOverlay`がnixpkgsに無いパッケージを取るのに使う
*/
{ lib, inputs }:
let
  localLib = {
    cpuOptimizedOverlay = import ./cpu-optimized-overlay.nix;
    cpuTargets = import ./cpu-targets.nix { inherit lib; };
    duplicates = import ./duplicates.nix { inherit lib; };
    fetchHuggingFace = pkgs: import ./fetch-hugging-face.nix { inherit pkgs; };
    hardening = import ./systemd-hardening.nix;
    importDirModules = import ./import-dir-modules.nix { inherit lib; };
    localPackagesOverlay = import ./local-packages-overlay.nix { inherit lib inputs localLib; };
    machineAddress4 = import ./machine-address4.nix { inherit lib; };
    microvmTap = import ./microvm-tap.nix;
    niks3PrivateTailscaleService = import ./niks3-private-tailscale-service.nix;
    niks3PrivateTailscaleUrl =
      tailnet: import ./niks3-private-tailscale-url.nix { inherit lib tailnet; };
    nixpkgsConfig = import ./nixpkgs-config.nix { inherit lib; };
    ollamaContext = import ./ollama-context.nix;
    ollamaModelNames = import ./ollama-model-names.nix;
    ollamaTailscaleService = import ./ollama-tailscale-service.nix;
    ollamaTailscaleUrl = import ./ollama-tailscale-url.nix { inherit lib; };
    parseIpv6 = import ./parse-ipv6.nix { inherit lib; };
    plamoTranslateModel = pkgs: import ./plamo-translate-model.nix { inherit pkgs; };
    publicDns = import ./public-dns.nix;
    tailnet = import ./tailnet.nix;
  };
in
localLib
