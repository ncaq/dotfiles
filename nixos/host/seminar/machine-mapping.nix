# seminarのコンテナとmicroVMへの、アドレスとIDの割り当て。
# オプションと重複の検査は`nixos/native-linux/machine-mapping.nix`が持っている。
{ lib, config, ... }:
{
  options = {
    /**
      microVMのvsock CID割り当て一覧です。
      vsock CIDは仮想マシンを識別するための32bit整数値で、
      以下の値が予約されています:

      - 0: ハイパバイザ
      - 1: ループバック
      - 2: ホスト
      - 0xFFFFFFFF: VMADDR_CID_ANY

      cloud-hypervisorはvsock経由でsystemd-notifyが使えるため、
      ホストのsystemdがVM内のサービス起動完了を正確に検知できます。
    */
    microvmCid = lib.mkOption {
      type = lib.types.attrsOf (lib.types.ints.between 3 4294967294);
      default = {
        mcp-nixos = 3;
        github-runner-dotfiles-x64 = 4;
        github-runner-cdn-ncaq-net-x64 = 5;
      };
      description = "vsock CID assignments for microVMs (must be >= 3, unique per VM)";
    };
  };

  config = {
    # ソートは重要度にするか悩ましいですが、IPアドレス剥き出しなここでは、IPアドレスでソートしておきます。
    #
    # `ipv4`を有効にしているマシンには、
    # IPv4でしか繋がらないインターネットの宛先へ出る用事があります。
    # その宛先を横に書いておきます。
    machineAddresses = {
      forgejo = {
        host6 = "fdf2:a855:5a3f:100::10";
        guest6 = "fdf2:a855:5a3f:100::11";
        # ミラーの取得元やwebhookの送信先のgithub.com。
        ipv4 = true;
      };
      # `fdf2:a855:5a3f:100::20`と`::21`は、
      # bulletと共通の`nixos/ollama/container.nix`がollamaへ割り当てています。
      mcp-nixos = {
        host6 = "fdf2:a855:5a3f:100::30";
        guest6 = "fdf2:a855:5a3f:100::31";
        # nixpkgsのコミットを引くapi.github.com。
        ipv4 = true;
      };
      github-runner-dotfiles-x64 = {
        host6 = "fdf2:a855:5a3f:100::40";
        guest6 = "fdf2:a855:5a3f:100::41";
        # github.comそのもの。
        ipv4 = true;
      };
      github-runner-cdn-ncaq-net-x64 = {
        host6 = "fdf2:a855:5a3f:100::50";
        guest6 = "fdf2:a855:5a3f:100::51";
        # github.comそのもの。
        ipv4 = true;
      };
      garage = {
        host6 = "fdf2:a855:5a3f:100::60";
        guest6 = "fdf2:a855:5a3f:100::61";
      };
      niks3-public = {
        host6 = "fdf2:a855:5a3f:100::70";
        guest6 = "fdf2:a855:5a3f:100::71";
        # GitHub ActionsのOIDCのissuerのtoken.actions.githubusercontent.com。
        ipv4 = true;
      };
      niks3-private = {
        host6 = "fdf2:a855:5a3f:100::80";
        guest6 = "fdf2:a855:5a3f:100::81";
      };
      open-webui = {
        host6 = "fdf2:a855:5a3f:100::90";
        guest6 = "fdf2:a855:5a3f:100::91";
        # web検索で開く任意のページ。
        ipv4 = true;
      };
      cdn = {
        host6 = "fdf2:a855:5a3f:100::100";
        guest6 = "fdf2:a855:5a3f:100::101";
      };
    };

    # ユーザはより汎用的なものを前に配置してソートします。
    # ollamaのIDは、bulletと共通の`nixos/ollama/container.nix`が割り当てています。
    serviceUser = {
      healthcheck = {
        uid = 976;
        gid = 976;
      };
      postgres = {
        # NixOSのデフォルトUID/GID(nixos/modules/misc/ids.nix)
        uid = 71;
        gid = 71;
      };
      garage = {
        uid = 979;
        gid = 979;
      };
      niks3-public = {
        uid = 978;
        gid = 978;
      };
      niks3-private = {
        uid = 977;
        gid = 977;
      };
      github-runner = {
        uid = 980;
        gid = 980;
      };
      forgejo = {
        uid = 991;
        gid = 986;
      };
      open-webui = {
        uid = 502;
        gid = 502;
      };
    };

    networking.nat.internalInterfaces = [ "vm-*" ]; # microVM TAP interfaces

    assertions =
      let
        inherit (import ../../../lib/duplicates.nix { inherit lib; }) findDuplicates formatDuplicates;

        cidEntries = lib.mapAttrsToList (name: value: { inherit name value; }) config.microvmCid;
        duplicateCidValues = findDuplicates (map (e: e.value) cidEntries);

        # 全てのmicroVMのNIC。
        # ホスト側のTAPの名前(`id`)とMACアドレスは、VMをまたいで重なってはいけない。
        vmInterfaces = lib.concatLists (
          lib.mapAttrsToList (
            vm: definition:
            map (interface: {
              inherit vm;
              inherit (interface) id mac;
            }) definition.config.config.microvm.interfaces
          ) config.microvm.vms
        );
        tapEntries = map (i: {
          name = i.vm;
          value = i.id;
        }) vmInterfaces;
        duplicateTapValues = findDuplicates (map (e: e.value) tapEntries);
        # Linuxのインタフェース名は15文字まで。
        # 超えると評価は通って、ホストでVMを起動する時にTAPの作成で初めて失敗する。
        longTapEntries = lib.filter (e: lib.stringLength e.value > 15) tapEntries;
        macEntries = map (i: {
          name = i.vm;
          value = i.mac;
        }) vmInterfaces;
        duplicateMacValues = findDuplicates (map (e: e.value) macEntries);
      in
      [
        {
          assertion = duplicateCidValues == [ ];
          message = "microvmCid values must be unique, but found duplicates: ${formatDuplicates toString cidEntries}";
        }
        {
          assertion = duplicateTapValues == [ ];
          message = "microVM TAP interface ids must be unique, but found duplicates: ${formatDuplicates lib.id tapEntries}";
        }
        {
          assertion = longTapEntries == [ ];
          message = "microVM TAP interface ids must be at most 15 characters, but found: ${
            lib.concatMapStringsSep ", " (e: "${e.value} (${e.name})") longTapEntries
          }";
        }
        {
          assertion = duplicateMacValues == [ ];
          message = "microVM MAC addresses must be unique, but found duplicates: ${formatDuplicates lib.id macEntries}";
        }
      ];
  };
}
