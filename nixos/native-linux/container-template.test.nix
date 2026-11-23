# `container-template.nix`が宣言から導く設定を確かめる。
#
# 実機のコンテナは全て正しく宣言しているので、
# 条件を取り違えたりフィルタを書き換えたりして導き方が崩れても、
# 評価は通ったまま気付けないことがある。
# 以下を見る。
#
# - `local.persist`を宣言すると`local.serviceUser`が有効になり、
#   ホストとコンテナの両方に同じIDのユーザができること
# - `serviceUser.<name>`の宣言が無い時に評価が止まること
# - `privateUsers`が`pick`ならidmap付きの`extraFlags`と`RequiresMountsFor`で、
#   それ以外なら`bindMounts`で、残すディレクトリを渡すこと
# - `machineAddresses.<name>`があるコンテナだけに、アドレスと名前解決の設定が入ること
#
# `container-template.nix`だけを`lib.evalModules`で読み込み、
# 参照している他のオプションは最小の形で用意する。
{ lib }:
let
  stub = {
    options = {
      # `container-template.nix`がホストへ入れる設定を受けるだけ。
      users = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      systemd = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      system.stateVersion = lib.mkOption {
        type = lib.types.str;
        default = "26.05";
      };
      time.timeZone = lib.mkOption {
        type = lib.types.str;
        default = "Asia/Tokyo";
      };
      # `machine-mapping.nix`のうち、読むものだけ。
      machineAddresses = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.nullOr lib.types.str));
        default = { };
      };
      serviceUser = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.int);
        default = { };
      };
      # `nixos-containers.nix`のうち、読むものと書くものだけ。
      containers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              autoStart = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              ephemeral = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              privateNetwork = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              privateUsers = lib.mkOption {
                type = lib.types.str;
                default = "no";
              };
              hostAddress = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              hostAddress6 = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              localAddress = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              localAddress6 = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              extraFlags = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              bindMounts = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
              config = lib.mkOption {
                type = lib.types.anything;
                default = { };
              };
            };
          }
        );
        default = { };
      };
    };
    # コンテナへ渡すだけなので中身は見ない。
    config._module.args.pkgs = { };
  };

  evaluate =
    declarations:
    (lib.evalModules {
      modules = [
        ./container-template.nix
        stub
        declarations
      ];
    }).config;

  evaluated = evaluate {
    machineAddresses.pick = {
      host6 = "fdf2:a855:5a3f:100::10";
      guest6 = "fdf2:a855:5a3f:100::11";
      host4 = null;
      guest4 = null;
    };
    serviceUser = {
      pick = {
        uid = 600;
        gid = 601;
      };
      identity = {
        uid = 602;
        gid = 603;
      };
    };
    containers = {
      # 既定の`pick`のままで、アドレスを持つ。
      pick.local.persist = [ "/var/lib/pick" ];
      # `identity`で、アドレスを持たない。
      identity = {
        privateUsers = "identity";
        local.persist = [ "/var/lib/identity" ];
      };
      # 何も宣言しない。
      plain = { };
    };
  };
  inherit (evaluated) containers;
  containerUnits = evaluated.systemd.services;

  # `serviceUser`の宣言が無いコンテナ。
  undeclared = evaluate { containers.missing.local.persist = [ "/var/lib/missing" ]; };
  evaluates = value: (builtins.tryEval (builtins.deepSeq value true)).success;

  show = builtins.toJSON;
in
assert lib.assertMsg (
  containers.pick.local.serviceUser && containers.identity.local.serviceUser
) "`local.persist`を宣言したコンテナの`local.serviceUser`が有効になりません";
assert lib.assertMsg (
  !containers.plain.local.serviceUser
) "何も宣言していないコンテナの`local.serviceUser`が有効になっています";
assert lib.assertMsg (
  evaluated.users.users == {
    pick = {
      uid = 600;
      group = "pick";
      isSystemUser = true;
    };
    identity = {
      uid = 602;
      group = "identity";
      isSystemUser = true;
    };
  }
) "ホスト側のユーザが違います: ${show evaluated.users.users}";
assert lib.assertMsg (
  evaluated.users.groups == {
    pick.gid = 601;
    identity.gid = 603;
  }
) "ホスト側のグループが違います: ${show evaluated.users.groups}";
assert lib.assertMsg (
  containers.pick.config.users == {
    users.pick = {
      uid = 600;
      group = "pick";
      isSystemUser = true;
    };
    groups.pick.gid = 601;
  }
) "コンテナ側のユーザが違います: ${show containers.pick.config.users}";
assert lib.assertMsg (!(containers.plain.config ? users)) "何も宣言していないコンテナにユーザが入っています";
assert lib.assertMsg (
  !(evaluates undeclared.users.users)
) "`serviceUser`の宣言が無いコンテナのホスト側のユーザが評価できてしまいます";
assert lib.assertMsg (
  !(evaluates undeclared.containers.missing.config.users)
) "`serviceUser`の宣言が無いコンテナのコンテナ側のユーザが評価できてしまいます";
assert lib.assertMsg (
  containers.pick.extraFlags == [ "--bind=/var/lib/pick:/var/lib/pick:idmap" ]
  && containers.pick.bindMounts == { }
) "`pick`のコンテナが残すディレクトリをidmap付きの`extraFlags`で渡していません";
assert lib.assertMsg (
  containerUnits."container@pick".unitConfig.RequiresMountsFor == [ "/var/lib/pick" ]
) "`pick`のコンテナの`RequiresMountsFor`が違います";
assert lib.assertMsg (
  containers.identity.extraFlags == [ ]
  &&
    containers.identity.bindMounts == {
      "/var/lib/identity" = {
        hostPath = "/var/lib/identity";
        isReadOnly = false;
      };
    }
) "`identity`のコンテナが残すディレクトリを`bindMounts`で渡していません";
assert lib.assertMsg (
  !(containerUnits ? "container@identity")
) "`bindMounts`で渡すコンテナに`RequiresMountsFor`を足しています";
assert lib.assertMsg (
  evaluated.systemd.tmpfiles.rules == [
    "d /var/lib/identity 0750 identity identity -"
    "d /var/lib/pick 0750 pick pick -"
  ]
) "残すディレクトリのtmpfilesの宣言が違います: ${show evaluated.systemd.tmpfiles.rules}";
assert lib.assertMsg (
  containers.pick.hostAddress6 == "fdf2:a855:5a3f:100::10"
  && containers.pick.localAddress6 == "fdf2:a855:5a3f:100::11"
  && containers.pick.hostAddress == null
  && containers.pick.localAddress == null
) "`machineAddresses`のあるコンテナのアドレスが違います";
assert lib.assertMsg (
  containers.pick.config.networking.useHostResolvConf == false
  && containers.pick.config.services.resolved.enable
) "アドレスを持つコンテナに名前解決の設定が入っていません";
assert lib.assertMsg (
  containers.identity.localAddress6 == null
  && !(containers.identity.config ? networking.useHostResolvConf)
  && !(containers.identity.config ? services.resolved.enable)
) "アドレスを持たないコンテナに名前解決の設定が入っています";
true
