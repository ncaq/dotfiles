/**
  コンテナとmicroVMのアドレスと、ホストと揃えるサービスユーザのIDの割り当て。

  ここはオプションと検査だけを持ち、値はコンテナを持つホストやモジュールが宣言する。
  `container-template.nix`が、コンテナと同じ名前の宣言を引いてコンテナへ割り当てる。
*/
{
  lib,
  config,
  localLib,
  ...
}:
let
  toAddress4 = localLib.machineAddress4;
  inherit (localLib) parseIpv6;
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
      default = { };
      description = "Network addresses for containers and microVMs";
    };

    serviceUser = lib.mkOption {
      type = lib.types.attrsOf userType;
      default = { };
      description = "Service user/group IDs (must match between host and isolated environment)";
    };
  };

  config = {
    networking = lib.mkIf (config.machineAddresses != { }) {
      nat = {
        enable = true;
        # ULAを持つコンテナとmicroVMをIPv6で外へ出す。
        # ホストにはLANの/64しか無くprefix delegationも無いので、
        # IPv4と同じくmasqueradeで出すしかない(`lib/machine-address4.nix`)。
        enableIPv6 = true;
        internalInterfaces = [ "ve-*" ]; # container veth interfaces
      };
      # NetworkManagerがコンテナのvethを管理しようとして競合するのを防ぐ。
      networkmanager.unmanaged = [ "interface-name:ve-*" ];
    };

    assertions =
      let
        inherit (localLib.duplicates) findDuplicates formatDuplicates;

        # IPv4はIPv6から単射で導くので、IPv6が重ならなければIPv4も重ならない。
        # IPv6だけを見れば足りる。
        # 同じアドレスでも書き方が違うと文字列としては重ならないので、
        # `lib/parse-ipv6.nix`で省略しない形に揃えてから比べる。
        # 読めないアドレスは揃えずにそのまま比べて、下の形の検査で報告する。
        normalizeAddress =
          address:
          let
            parsed = parseIpv6 address;
          in
          if parsed == null then address else parsed;
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
        duplicateUidValues = findDuplicates (map (e: e.value) uidEntries);

        gidEntries = lib.mapAttrsToList (name: user: {
          inherit name;
          value = user.gid;
        }) config.serviceUser;
        duplicateGidValues = findDuplicates (map (e: e.value) gidEntries);
      in
      [
        {
          assertion = duplicateAddressValues == [ ];
          message = "machineAddresses must be unique, but found duplicates: ${formatDuplicates lib.id normalizedAddressEntries}";
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
          message = "serviceUser uid values must be unique, but found duplicates: ${formatDuplicates toString uidEntries}";
        }
        {
          assertion = duplicateGidValues == [ ];
          message = "serviceUser gid values must be unique, but found duplicates: ${formatDuplicates toString gidEntries}";
        }
      ];
  };
}
