{ inputs, ... }: {
  imports = [ inputs.comfyui-nix.nixosModules.default ];
  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;
    port = 8188; # デフォルトですが競合しやすいポートという性質上明示しておきます。
    listenAddress = "127.0.0.1"; # "0.0.0.0"にすると外部からアクセス可能になります。
    dataDir = "/var/lib/comfyui";
    openFirewall = false; # デフォルトですが分かり易いように明示しておきます。
  };
}
