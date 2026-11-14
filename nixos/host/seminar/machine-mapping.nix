{ lib, config, ... }:
let
  toAddress4 = ipv6: import ../../../lib/machine-address4.nix { inherit lib ipv6; };
  addressType = lib.types.submodule (
    { config, ... }:
    {
      options = {
        host6 = lib.mkOption {
          type = lib.types.str;
          description = "Host-side IPv6 address (ULA)";
        };
        guest6 = lib.mkOption {
          type = lib.types.str;
          description = "Guest-side IPv6 address (ULA, container or microVM)";
        };
        # IPv4はIPv6から導くので宣言せず、持たせるかどうかだけを選ぶ。
        # 導き方と、ULAにしている理由は`lib/machine-address4.nix`に書いてある。
        ipv4 = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to give the machine IPv4 addresses as well.
            Only for machines that must reach IPv4-only destinations on the internet,
            which also requires `local.machineEgress.<name>.internet`.
            The host and other machines always talk to it over IPv6.
          '';
        };
        host4 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          default = if config.ipv4 then toAddress4 config.host6 else null;
          defaultText = lib.literalMD "`ipv4`の時は`lib/machine-address4.nix`で`host6`から導いたアドレス、それ以外は`null`";
          description = "Host-side IPv4 address derived from `host6`, or null without `ipv4`";
        };
        guest4 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          default = if config.ipv4 then toAddress4 config.guest6 else null;
          defaultText = lib.literalMD "`ipv4`の時は`lib/machine-address4.nix`で`guest6`から導いたアドレス、それ以外は`null`";
          description = "Guest-side IPv4 address derived from `guest6`, or null without `ipv4`";
        };
      };
    }
  );
  userType = lib.types.submodule {
    options = {
      uid = lib.mkOption {
        type = lib.types.int;
        description = "Service user ID (must match between host and isolated environment)";
      };
      gid = lib.mkOption {
        type = lib.types.int;
        description = "Service group ID (must match between host and isolated environment)";
      };
    };
  };
in
{
  options = {
    machineAddresses = lib.mkOption {
      type = lib.types.attrsOf addressType;
      default = {
        # ソートは重要度にするか悩ましいですが、IPアドレス剥き出しなここでは、IPアドレスでソートしておきます。
        #
        # `ipv4`を有効にしているマシンには、
        # IPv4でしか繋がらないインターネットの宛先へ出る用事があります。
        # その宛先を横に書いておきます。
        forgejo = {
          host6 = "fdf2:a855:5a3f:100::10";
          guest6 = "fdf2:a855:5a3f:100::11";
          # ミラーの取得元やwebhookの送信先のgithub.com。
          ipv4 = true;
        };
        # 実際のアドレスは`nixos/ollama/container.nix`がbulletと共通の値で持っています。
        # ここでは他のマシンと重ならないように同じ値を予約しています。
        ollama = {
          host6 = "fdf2:a855:5a3f:100::20";
          guest6 = "fdf2:a855:5a3f:100::21";
          # 手でpullするhf.coのモデルの配信元のcas-bridge.xethub.hf.co。
          ipv4 = true;
        };
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
      description = "Network addresses for containers and microVMs";
    };

    serviceUser = lib.mkOption {
      type = lib.types.attrsOf userType;
      default = {
        # ユーザはより汎用的なものを前に配置してソートします。
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
        ollama = {
          uid = 501;
          gid = 501;
        };
        open-webui = {
          uid = 502;
          gid = 502;
        };
      };
      description = "Service user/group IDs (must match between host and isolated environment)";
    };

    /**
      microVMのvsock CID割り当て一覧です。
      vsock CIDは仮想マシンを識別するための32bit整数値で、
      以下の値が予約されています:

      - 0: ハイパーバイザー
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
    networking.nat = {
      enable = true;
      # ULAを持つコンテナとmicroVMをIPv6で外へ出す。
      # ホストにはLANの/64しか無くprefix delegationも無いので、
      # IPv4と同じくmasqueradeで出すしかない(`lib/machine-address4.nix`)。
      enableIPv6 = true;
      internalInterfaces = [
        "ve-*" # container veth interfaces
        "vm-*" # microVM TAP interfaces
      ];
    };

    assertions =
      let
        findDuplicates = list: lib.unique (lib.filter (x: lib.count (y: x == y) list > 1) list);

        # { name, value } のリストから重複を検出し「値 (名前1, 名前2)」形式で報告
        formatDuplicates =
          toStr: entries:
          let
            values = map (e: e.value) entries;
            dups = findDuplicates values;
            namesForValue =
              dupVal:
              let
                matched = lib.filter (e: e.value == dupVal) entries;
              in
              lib.concatMapStringsSep ", " (e: e.name) matched;
          in
          lib.concatMapStringsSep "; " (dupVal: "${toStr dupVal} (${namesForValue dupVal})") dups;

        cidEntries = lib.mapAttrsToList (name: value: { inherit name value; }) config.microvmCid;
        cidValues = map (e: e.value) cidEntries;
        duplicateCidValues = findDuplicates cidValues;

        # IPv4はIPv6から単射で導くので、IPv6が重ならなければIPv4も重ならない。
        # IPv6だけを見れば足りる。
        # 同じアドレスでも書き方が違うと文字列としては重ならないので、
        # `lib.network.ipv6.fromString`で省略しない形に揃えてから比べる。
        # 読めないアドレスは揃えずにそのまま比べて、下の形の検査で報告する。
        normalizeAddress =
          address:
          let
            result = builtins.tryEval (lib.network.ipv6.fromString address).address;
          in
          if result.success then result.value else address;
        addressEntries = lib.concatLists (
          lib.mapAttrsToList (name: entry: [
            {
              name = "${name}.host6";
              value = entry.host6;
            }
            {
              name = "${name}.guest6";
              value = entry.guest6;
            }
          ]) config.machineAddresses
        );
        normalizedAddressEntries = map (e: e // { value = normalizeAddress e.value; }) addressEntries;
        duplicateAddressValues = findDuplicates (map (e: e.value) normalizedAddressEntries);
        # IPv4を持たないマシンのアドレスも、IPv4を導ける形に揃えておく。
        # 後から`ipv4`を有効にした時に初めて評価で止まることが無いようにする。
        malformedAddressEntries = lib.filter (
          e: !(builtins.tryEval (builtins.deepSeq (toAddress4 e.value) true)).success
        ) addressEntries;

        # IPv4はインターネットのIPv4だけの宛先へ出るためだけに持たせるので、
        # インターネットへ出られないマシンに付いていたら外し忘れ。
        ipv4WithoutInternet = lib.attrNames (
          lib.filterAttrs (
            name: entry: entry.ipv4 && !(config.local.machineEgress.${name}.internet or false)
          ) config.machineAddresses
        );

        uidEntries = lib.mapAttrsToList (name: user: {
          inherit name;
          value = user.uid;
        }) config.serviceUser;
        uidValues = map (e: e.value) uidEntries;
        duplicateUidValues = findDuplicates uidValues;

        gidEntries = lib.mapAttrsToList (name: user: {
          inherit name;
          value = user.gid;
        }) config.serviceUser;
        gidValues = map (e: e.value) gidEntries;
        duplicateGidValues = findDuplicates gidValues;

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
        # Linuxのインターフェイス名は15文字まで。
        # 超えると評価は通って、ホストでVMを起動する時にTAPの作成で初めて失敗する。
        longTapEntries = lib.filter (e: lib.stringLength e.value > 15) tapEntries;
        macEntries = map (i: {
          name = i.vm;
          value = i.mac;
        }) vmInterfaces;
        duplicateMacValues = findDuplicates (map (e: e.value) macEntries);

        cidDups = formatDuplicates toString cidEntries;
        addrDups = formatDuplicates lib.id normalizedAddressEntries;
        uidDups = formatDuplicates toString uidEntries;
        gidDups = formatDuplicates toString gidEntries;
      in
      [
        {
          assertion = duplicateCidValues == [ ];
          message = "microvmCid values must be unique, but found duplicates: ${cidDups}";
        }
        {
          assertion = duplicateAddressValues == [ ];
          message = "machineAddresses must be unique, but found duplicates: ${addrDups}";
        }
        {
          assertion = malformedAddressEntries == [ ];
          message = "machineAddresses must be written as fdf2:a855:5a3f:<0-255>::<0-255> (see lib/machine-address4.nix), but found: ${
            lib.concatMapStringsSep ", " (e: "${e.value} (${e.name})") malformedAddressEntries
          }";
        }
        {
          assertion = ipv4WithoutInternet == [ ];
          message = "machineAddresses: IPv4 is only for reaching IPv4-only destinations on the internet, but these machines have it without local.machineEgress.<name>.internet: ${lib.concatStringsSep ", " ipv4WithoutInternet}";
        }
        {
          assertion = duplicateUidValues == [ ];
          message = "serviceUser uid values must be unique, but found duplicates: ${uidDups}";
        }
        {
          assertion = duplicateGidValues == [ ];
          message = "serviceUser gid values must be unique, but found duplicates: ${gidDups}";
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
