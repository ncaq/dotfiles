/**
  NixOS Containerの定義の定型を、`containers.<name>`自身に持たせる。

  どのコンテナにも同じ形で書いていたものを、
  既定値と`containers.<name>.local`の宣言から生成する。
  個々のコンテナの定義には、そのコンテナに固有のことだけが残る。

  別の名前空間にせず`containers`のsubmoduleを拡張しているのは、
  ここで表せないものを素の`containers.<name>`のオプションでそのまま書けるようにするため。
  既定値は全て`mkDefault`なので、個々のコンテナで上書きできる。

  # 全てのコンテナの既定値

  - `autoStart`: ブート時に起動する。ソケットで起動するコンテナだけが切る
  - `ephemeral`: ルートを毎回作り直して、残すものは`local.persist`で明示する
  - `privateNetwork`: ホストのネットワークから隔離する
  - `privateUsers = "pick"`: 毎起動ランダムな高位のUID範囲へマップして、
    コンテナを脱出されてもホスト上では無権限のUIDになるようにする。
    `identity`と違ってコンテナ内のrootがホストのUID 0を持たない
  - `system.stateVersion`と`time.timeZone`: ホストと同じ値。
    コンテナにはホストのタイムゾーンが伝播しないので、
    渡さないとUTCになってログやファイル名の時刻がホストとずれる

  # アドレス

  `machineAddresses.<name>`があれば、それをvethのアドレスにする。
  アドレスを持つコンテナは、名前解決をコンテナの中のsystemd-resolvedに任せる。
  ホストの`resolv.conf`が指すのはホストのloopbackのスタブで、
  自分のネットワークを持つコンテナからは届かない。
  フォールバックのDNSサーバは`networking.nix`が揃えている。

  `networking.useHostResolvConf`を切るのは、
  nixpkgsのresolvedのモジュールが有効なままだと評価を止めるため。
  コンテナ向けの既定値は`mkDefault true`なので、`mkForce`は要らない。

  # `local.serviceUser`

  `serviceUser.<name>`のIDで、コンテナと同じ名前のユーザとグループを、
  ホストとコンテナの両方に作る。
  ephemeralなコンテナでは動的に割り当てたIDの記録が起動ごとに消えるので、
  bind mountしたディレクトリの所有権がずれないようにIDを固定する。
  ホスト側にも作るのは、その所有者をホストから名前で扱うため。

  # `local.persist`

  コンテナの再作成をまたいで残すディレクトリ。
  ホストとコンテナで同じパスになる。
  ホスト側に`0750`でサービスユーザの所有として用意して、コンテナへ読み書きできる形で渡す。

  `pick`では素のbind mountだと所有者が無効なUIDに見えて書き込めないので、
  idmapで数値のIDをホストとコンテナで同一視させる。
  `bindMounts`はマウントオプションを渡せないので`extraFlags`で渡す。
  `extraFlags`のbind mountには`bindMounts`と違って`RequiresMountsFor`が自動で付かないので、
  それもここで足す。
*/
{ lib, config, ... }:
let
  hostConfig = config;
  idsOf =
    name:
    hostConfig.serviceUser.${name}
      or (throw "containers.${name}.local.serviceUser: serviceUser.${name}が宣言されていません");
  userOf = name: {
    inherit (idsOf name) uid;
    group = name;
    isSystemUser = true;
  };
  withServiceUser = lib.filterAttrs (_: c: c.local.serviceUser) config.containers;
  withPersist = lib.filterAttrs (_: c: c.local.persist != [ ]) config.containers;
  usesIdmap = c: c.privateUsers == "pick";
in
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          cfg = config.local;
          addr = hostConfig.machineAddresses.${name} or null;
          networked = config.localAddress6 != null || config.localAddress != null;
        in
        {
          options.local = {
            serviceUser = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                `serviceUser.<name>`のIDで、コンテナと同じ名前のユーザとグループを、
                ホストとコンテナの両方に作るか。
              '';
            };
            persist = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ ];
              description = ''
                コンテナの再作成をまたいで残すディレクトリ。
                ホストとコンテナで同じパスになり、サービスユーザが所有する。
              '';
            };
          };

          config = lib.mkMerge [
            {
              autoStart = lib.mkDefault true;
              ephemeral = lib.mkDefault true;
              privateNetwork = lib.mkDefault true;
              privateUsers = lib.mkDefault "pick";
              config = {
                system.stateVersion = lib.mkDefault hostConfig.system.stateVersion;
                time.timeZone = lib.mkDefault hostConfig.time.timeZone;
                networking.useHostResolvConf = lib.mkIf networked false;
                services.resolved.enable = lib.mkIf networked (lib.mkDefault true);
                users = lib.mkIf cfg.serviceUser {
                  users.${name} = userOf name;
                  groups.${name}.gid = (idsOf name).gid;
                };
              };
            }
            (lib.mkIf (addr != null) {
              hostAddress6 = lib.mkDefault addr.host6;
              localAddress6 = lib.mkDefault addr.guest6;
              hostAddress = lib.mkDefault addr.host4;
              localAddress = lib.mkDefault addr.guest4;
            })
            (lib.mkIf (usesIdmap config) {
              extraFlags = map (path: "--bind=${path}:${path}:idmap") cfg.persist;
            })
            (lib.mkIf (!usesIdmap config) {
              bindMounts = lib.genAttrs cfg.persist (path: {
                hostPath = path;
                isReadOnly = false;
              });
            })
          ];
        }
      )
    );
  };

  config = {
    users = {
      users = lib.mapAttrs (name: _: userOf name) withServiceUser;
      groups = lib.mapAttrs (name: _: { inherit (idsOf name) gid; }) withServiceUser;
    };

    systemd = {
      tmpfiles.rules = lib.concatLists (
        lib.mapAttrsToList (
          name: c: map (path: "d ${path} 0750 ${name} ${name} -") c.local.persist
        ) withPersist
      );
      services = lib.mapAttrs' (
        name: c: lib.nameValuePair "container@${name}" { unitConfig.RequiresMountsFor = c.local.persist; }
      ) (lib.filterAttrs (_: usesIdmap) withPersist);
    };

    assertions = [
      (
        let
          ownerless = lib.attrNames (lib.filterAttrs (_: c: !c.local.serviceUser) withPersist);
        in
        {
          assertion = ownerless == [ ];
          message = "containers.<name>.local.persist: 所有者になるサービスユーザが要るので`local.serviceUser`も有効にしてください: ${lib.concatStringsSep ", " ownerless}";
        }
      )
    ];
  };
}
