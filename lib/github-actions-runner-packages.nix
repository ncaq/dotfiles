/**
  GitHub ActionsのUbuntu 26.04ランナ互換Nixパッケージリスト。

  - バージョンはnixpkgsのリビジョンに依存するため完全一致ではありません。
  - ひとまずは既定のバージョンだけを有効にしています。
  - nixpkgsの既定のバージョンがランナの既定より古い言語やデータベースは、
    ランナの既定に合わせたバージョンを明示して、
    nixpkgsの既定のバージョンも`nixpkgsDefaultVersions`として後ろに加えます。
    nixpkgsの既定が追いついた時はそちらを残すだけで済みます。
  - nixpkgsにランナと同じメジャーバージョンが無いものは、
    互換性の無いものが入っていて混乱しないように含めません。
  - Android SDKはnixpkgs単体では難しいです。android-nixpkgs等を別途利用推奨。今回非対応。
  - unfreeなパッケージは現在無効にしています。

  参照元: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md
  イメージバージョン: 20261111.196.1
*/
{ pkgs, ... }:
with pkgs;
let
  # 暗黙のうちに要求されることが多いパッケージ。
  basicLanguageAndRuntime = [
    bash
    go
    nodejs
    perl
    python314
  ];

  # ビルドに手間がかかるパッケージ。
  extendLanguageAndRuntime = [
    # ghcupは除外します。
    # NixOSで動くghcのビルド済み配布物が無いので、
    # nixpkgsが`haskellPackages.ghcup`を評価時にエラーにしています。
    cabal-install
    cargo
    clippy
    dotnet-sdk
    gcc
    gfortran
    haskell.compiler.ghc914
    jdk25
    kotlin
    llvmPackages.clang
    llvmPackages.clang-tools
    php85
    php85Packages.composer
    powershell
    ruby
    rustc
    rustfmt
    stack
    # swiftはランナが6系でstableのnixpkgsには5系しかないので除外。
  ];

  packageManagement = [
    # npmはnodejsに同梱。
    pipx
    vcpkg
    yarn

    # HomebrewはNix環境では不要/非推奨。
  ];

  # C/C++ビルド関係ツールは様々なシステムが依存しています。
  cppBuildTools = [
    autoconf
    automake
    bison
    cmake
    flex
    gnumake
    libtool
    ninja
    pkg-config
    swig
  ];

  javaBuildTools = [
    ant
    gradle
    maven
  ];

  # クロスコンパイルに問題があります。
  bazelTools = [
    bazel
    bazelisk
  ];

  containerTools = [
    amazon-ecr-credential-helper
    buildah
    docker-client # CLI, buildx, compose。daemonはパッケージ単位で導入するのは望ましくないので除外。
    podman
    skopeo
  ];

  kubernetesTools = [
    kind
    kubectl
    # helmはランナが4系でstableのnixpkgsには3系しかないので除外。
    kustomize
    minikube
  ];

  infrastructureAsCode = [
    # packerを含むHashiCorp製品はbslなため除外。
    ansible
    bicep
  ];

  cloudClis = [
    awscli2
    azure-cli
    google-cloud-sdk
    ssm-session-manager-plugin
  ];

  cliTools = [
    # Version Control
    git
    git-ftp
    git-lfs

    # GitHub CLI
    gh

    # Data Processing
    jq
    yq-go

    # Compression
    _7zz # 7zip
    brotli
    bzip2
    lz4
    pigz
    unzip
    upx
    xz
    zip
    zstd

    # Network
    aria2
    bind.dnsutils # dig, nslookup, nsupdate
    curl
    inetutils # ftp, telnet
    iproute2
    iputils # ping
    netcat-openbsd
    openssh
    rsync
    sshpass
    wget

    # File / Text
    coreutils
    file
    findutils
    parallel
    patchelf
    shellcheck
    tree
    yamllint

    # Security
    gnupg
    nss.tools # certutil等(libnss3-tools相当)
    openssl

    # Misc
    texinfo
    time
    tk
    xvfb-run
    zsync

    # Fonts
    noto-fonts-color-emoji
  ];

  systemTools = [
    acl
    dbus
    fakeroot
  ];

  otherDistributionTools = [
    dpkg
    rpm
  ];

  browsers = [
    chromedriver
    chromium
    firefox
    geckodriver
    selenium-server-standalone
    # `google-chrome`, `microsoft-edge`は`allowUnfree = true`が必要。
  ];

  databases = [
    mysql84 # nixpkgsにはバージョンの無い`mysql`がありません。
    postgresql_18
    sqlite
  ];

  webServers = [
    apacheHttpd
    nginx
  ];

  devLibraries = [
    jitterentropy # libjitterentropy3-dev
    libxcrypt # libcrypt-dev
    libyaml
    openssl.dev
    sqlite.dev
  ];

  additionalTools = [
    azure-storage-azcopy # azcopy

    # nvmはnixpkgsにない。
    # codeqlはunfreeのため除外。
  ];

  # 上でランナの既定に合わせたバージョンを明示したもののnixpkgsの既定のバージョン。
  # `extraPackages`はsystemdの`path`になり先にあるものが優先されるので、
  # ランナの既定が優先されるように`all`の最後に置きます。
  nixpkgsDefaultVersions = [
    ghc
    jdk
    php
    postgresql
    python3
  ];

in
{
  all = builtins.concatLists [
    basicLanguageAndRuntime
    extendLanguageAndRuntime
    packageManagement
    cppBuildTools
    javaBuildTools
    bazelTools
    containerTools
    kubernetesTools
    infrastructureAsCode
    cloudClis
    cliTools
    systemTools
    otherDistributionTools
    browsers
    databases
    webServers
    devLibraries
    additionalTools
    nixpkgsDefaultVersions
  ];

  minimal = builtins.concatLists [
    basicLanguageAndRuntime
    cppBuildTools
    cliTools
    systemTools
    devLibraries
  ];

  inherit
    basicLanguageAndRuntime
    extendLanguageAndRuntime
    packageManagement
    cppBuildTools
    javaBuildTools
    bazelTools
    containerTools
    kubernetesTools
    infrastructureAsCode
    cloudClis
    cliTools
    systemTools
    otherDistributionTools
    browsers
    databases
    webServers
    devLibraries
    additionalTools
    nixpkgsDefaultVersions
    ;
}
