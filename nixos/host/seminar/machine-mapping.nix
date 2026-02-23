{ lib, config, ... }:
let
  addressType = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Host-side IP address";
      };
      guest = lib.mkOption {
        type = lib.types.str;
        description = "Guest-side IP address (container or microVM)";
      };
    };
  };
  userType = lib.types.submodule {
    options = {
      uid = lib.mkOption {
        type = lib.types.int;
        description = "Container user ID (must match between host and container)";
      };
      gid = lib.mkOption {
        type = lib.types.int;
        description = "Container group ID (must match between host and container)";
      };
    };
  };
in
{
  options.machineAddresses = lib.mkOption {
    type = lib.types.attrsOf addressType;
    default = {
      forgejo = {
        host = "192.168.100.10";
        guest = "192.168.100.11";
      };
      atticd = {
        host = "192.168.100.20";
        guest = "192.168.100.21";
      };
      mcp-nixos = {
        host = "192.168.100.30";
        guest = "192.168.100.31";
      };
      github-runner-x64 = {
        host = "192.168.100.40";
        guest = "192.168.100.41";
      };
      github-runner-arm64 = {
        host = "192.168.100.50";
        guest = "192.168.100.51";
      };
    };
    description = "Network addresses for containers and microVMs";
  };

  options.containerUsers = lib.mkOption {
    type = lib.types.attrsOf userType;
    default = {
      forgejo = {
        uid = 991;
        gid = 986;
      };
      atticd = {
        uid = 993;
        gid = 988;
      };
      github-runner = {
        uid = 980;
        gid = 980;
      };
    };
    description = "Container user/group IDs (must match between host and container)";
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
  options.microvmCid = lib.mkOption {
    type = lib.types.attrsOf (lib.types.ints.between 3 4294967294);
    default = {
      mcp-nixos = 3;
      github-runner-arm64 = 4;
    };
    description = "vsock CID assignments for microVMs (must be >= 3, unique per VM)";
  };

  config = {
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
              dupVal: lib.concatMapStringsSep ", " (e: e.name) (lib.filter (e: e.value == dupVal) entries);
          in
          lib.concatMapStringsSep "; " (dupVal: "${toStr dupVal} (${namesForValue dupVal})") dups;

        cidEntries = lib.mapAttrsToList (name: value: { inherit name value; }) config.microvmCid;
        cidValues = map (e: e.value) cidEntries;
        duplicateCidValues = findDuplicates cidValues;

        addressEntries = lib.concatLists (
          lib.mapAttrsToList (name: entry: [
            {
              name = "${name}.host";
              value = entry.host;
            }
            {
              name = "${name}.guest";
              value = entry.guest;
            }
          ]) config.machineAddresses
        );
        addressValues = map (e: e.value) addressEntries;
        duplicateAddressValues = findDuplicates addressValues;

        uidEntries = lib.mapAttrsToList (name: user: {
          inherit name;
          value = user.uid;
        }) config.containerUsers;
        uidValues = map (e: e.value) uidEntries;
        duplicateUidValues = findDuplicates uidValues;

        gidEntries = lib.mapAttrsToList (name: user: {
          inherit name;
          value = user.gid;
        }) config.containerUsers;
        gidValues = map (e: e.value) gidEntries;
        duplicateGidValues = findDuplicates gidValues;
      in
      [
        {
          assertion = duplicateCidValues == [ ];
          message = "microvmCid values must be unique, but found duplicates: ${formatDuplicates toString cidEntries}";
        }
        {
          assertion = duplicateAddressValues == [ ];
          message = "machineAddresses must be unique, but found duplicates: ${formatDuplicates lib.id addressEntries}";
        }
        {
          assertion = duplicateUidValues == [ ];
          message = "containerUsers uid values must be unique, but found duplicates: ${formatDuplicates toString uidEntries}";
        }
        {
          assertion = duplicateGidValues == [ ];
          message = "containerUsers gid values must be unique, but found duplicates: ${formatDuplicates toString gidEntries}";
        }
      ];

    networking.nat = {
      enable = true;
      internalInterfaces = [
        "ve-+" # container veth interfaces
        "vm-+" # microVM TAP interfaces
      ];
    };
  };
}
