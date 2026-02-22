/**
  GitHub ActionsのUbuntu 24.04ランナー互換Nixパッケージリスト。

  - バージョンはnixpkgsのリビジョンに依存するため完全一致ではありません。
  - ひとまずは標準的なバージョンだけを有効にしています。
  - Android SDKはnixpkgs単体では難しいです。android-nixpkgs等を別途利用推奨。今回非対応。
  - unfreeなパッケージは現在無効にしています。

  参照元: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
  イメージバージョン: 20260201.15.1
*/
{ pkgs }:
with pkgs;
let
  # 暗黙のうちに要求されることが多いパッケージ。
  basicLanguageAndRuntime = [
    bash
    go
    nodejs
    perl
    python3
  ];

  # ビルドに手間がかかるパッケージ。
  extendLanguageAndRuntime = [
    # ghcupは現在nixpkgsでbroken指定されているので除外します。
    # swiftは現在ビルドに失敗するため除外します。
    cabal-install
    cargo
    clippy
    dotnet-sdk
    gcc
    gfortran
    ghc
    jdk
    julia
    kotlin
    llvmPackages.clang
    llvmPackages.clang-tools
    php
    phpPackages.composer
    powershell
    ruby
    rustc
    rustfmt
    stack
  ];

  packageManagement = [
    # npmはnodejsに同梱。
    lerna
    yarn

    pipx

    vcpkg

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
    kubernetes-helm
    kustomize
    minikube
  ];

  infrastructureAsCode = [
    # packerを含むHashiCorp製品はbslなため除外。
    ansible
    bicep
    pulumi
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
    mercurial

    # GitHub CLI
    gh

    # Data Processing
    jq
    yq

    # Compression
    brotli
    bzip2
    lz4
    p7zip
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

    # Media
    mediainfo

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
    haveged
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
    mariadb # MySQL互換、nixpkgsではこちらがよりよくメンテナンスされています。
    postgresql
    sqlite
  ];

  webServers = [
    apacheHttpd
    nginx
  ];

  devLibraries = [
    libyaml
    openssl.dev
    sqlite.dev
  ];

  additionalTools = [
    azure-storage-azcopy # azcopy
    fastlane
    newman
    sphinxsearch

    # nvm, parcelはnixpkgsにない。
    # codeqlはunfreeのため除外。
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
    ;
}
