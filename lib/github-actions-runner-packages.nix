/**
  GitHub ActionsのUbuntu 24.04ランナー互換Nixパッケージリスト。

  - バージョンはnixpkgsのリビジョンに依存するため完全一致ではありません。
  - ひとまずは標準的なバージョンだけを有効にしています。
  - Android SDKはnixpkgs単体では難しいです。android-nixpkgs等を別途利用推奨。今回非対応。
  - `allowUnfree = true`が必要なパッケージあり。デフォルトでは無効にします。

  参照元: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
  イメージバージョン: 20260201.15.1
*/
{ pkgs }:
let
  languageAndRuntime = with pkgs; [
    # Rust
    cargo
    clippy
    rustc
    rustfmt

    # Haskell
    # ghcupはnixpkgsではbroken指定されているので除外します。
    cabal-install
    ghc
    stack

    bash
    dotnet-sdk
    gcc
    gfortran
    go
    jdk
    julia
    kotlin
    llvmPackages.clang
    llvmPackages.clang-tools
    nodejs
    perl
    php
    phpPackages.composer
    powershell
    python3
    ruby
    swift
  ];

  packageManagement = with pkgs; [
    # npmはnodejsに同梱。
    lerna
    yarn

    pipx

    kubernetes-helm
    vcpkg

    # HomebrewはNix環境では不要/非推奨。
  ];

  projectManagement = with pkgs; [
    # Javaビルドツール
    ant
    gradle
    maven

    # C/C++ビルドツール
    autoconf
    automake
    cmake
    gnumake
    libtool
    ninja
    pkg-config

    # Parser generators
    bison
    flex

    # その他
    swig
  ];

  devopsTools = with pkgs; [
    # Configuration Management
    ansible

    # Cloud CLIs
    awscli2
    azure-cli
    google-cloud-sdk
    ssm-session-manager-plugin

    # GitHub
    gh

    # Infrastructure as Code
    bicep
    packer
    pulumi

    # Container Tools
    buildah
    docker # Docker CLI + daemon
    docker-buildx
    docker-compose # Docker Compose v2 plugin
    podman
    skopeo

    # Container Registry
    amazon-ecr-credential-helper

    # Kubernetes Tools
    kind
    kubectl
    kustomize
    minikube

    # Bazel
    bazel
    bazelisk
  ];

  cliTools = with pkgs; [
    # Version Control
    git
    git-ftp
    git-lfs
    mercurial

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

    # System
    acl
    dbus
    dpkg
    fakeroot
    haveged
    rpm

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

  browsers = with pkgs; [
    chromedriver
    chromium
    firefox
    geckodriver
    selenium-server-standalone
    # google-chromeは`allowUnfree = true`が必要。
    # Microsoft Edgeはnixpkgsに公式パッケージなし。
  ];

  databases = with pkgs; [
    mariadb # MySQL互換、nixpkgsではこちらがよりよくメンテナンスされています。
    postgresql
    sqlite
  ];

  webServers = with pkgs; [
    apacheHttpd
    nginx
  ];

  devLibraries = with pkgs; [
    libyaml
    openssl.dev
    sqlite.dev
  ];

  additionalTools = with pkgs; [
    azure-storage-azcopy # azcopy
    fastlane
    newman
    sphinxsearch

    # CodeQL, nvm, parcelはnixpkgsにない。
  ];

in
{
  all = builtins.concatLists [
    languageAndRuntime
    packageManagement
    projectManagement
    devopsTools
    cliTools
    browsers
    databases
    webServers
    devLibraries
    additionalTools
  ];

  inherit
    languageAndRuntime
    packageManagement
    projectManagement
    devopsTools
    cliTools
    browsers
    databases
    webServers
    devLibraries
    additionalTools
    ;
}
