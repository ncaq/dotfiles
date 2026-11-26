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

  # `pkgs`

  コンテナの中の`pkgs`を、ホストの`pkgs`と同じインスタンスにする。
  コンテナは既定ではホストの`pkgs`を引き継がず、
  コンテナごとにnixpkgsを読み込み直す。
  同じパッケージのderivationをコンテナの数だけ評価し直すことになり、
  `nix-eval-jobs`のワーカは評価中にGCをしないので、その分がそのままメモリの使用量に積み上がる。
  コンテナを8つ持つseminarでは、
  ホストの構成の評価が確保する量がこれで約17%減った。

  ホストの`pkgs`を渡すので、
  コンテナの中のパッケージにもホストのoverlayとunfreeの許可が効く。

  # アドレス

  `machineAddresses.<name>`があれば、それをvethのアドレスにする。
  アドレスを持つコンテナは、名前解決をコンテナの中のsystemd-resolvedに任せる。
  ホストの`resolv.conf`が指すのはホストのloopbackのスタブで、
  自分のネットワークを持つコンテナからは届かない。
  フォールバックのDNSサーバは`networking.nix`が揃えている。

  `networking.useHostResolvConf`を切るのは、
  nixpkgsのresolvedのモジュールが有効なままだと評価を止めるため。
  コンテナ向けの既定値は`mkDefault true`なので、`mkForce`は要らない。

  # ホスト側のveth

  vethのアドレスを持つコンテナは、
  ホスト側のアドレスとコンテナ宛のルートをsystemd-networkdで設定する。

  nixpkgsのコンテナのモジュールは、これらを`container@<name>.service`の`postStart`で設定する。
  `postStart`はコンテナの中の起動が終わってreadyになるまで動かないので、
  コンテナの中のサービスが起動する時点では、ホスト側に戻りの経路がまだ無い。
  起動の途中で外へ繋ぐサービスは応答を受け取れず、
  タイムアウトで一度失敗して、それからコンテナがreadyになる。
  systemd-networkdはvethが作られた直後に設定するので、この順序の問題が起きない。

  `postStart`は空にする。
  残すと`ip addr add`と`ip route add`が、systemd-networkdが先に設定したものと衝突して失敗する。
  空にすると`extraVeths`の設定も消えるので、`extraVeths`を持つコンテナは評価を止める。

  `.network`の`matchConfig.Name`には`local.hostInterface`を使わず、
  完全な`ve-<コンテナ名>`を書く。
  systemd-networkdの`Name=`はaltnameにも一致するので、
  名前が15文字を超えて主名が縮められても一致する。
  `local.hostInterface`は超えた時にワイルドカードになり、
  同じ先頭を持つ他のコンテナのvethにも同じアドレスを付けてしまう。

  ここで宣言する`.network`が先に一致するので、
  systemdに同梱の`80-container-ve.network`はこれらのvethには使われない。
  あちらが有効にするDHCPサーバやmasqueradeには頼っていない。
  外へ出る経路は`machine-mapping.nix`がNATモジュールで作っている。

  # `local.hostInterface`

  vethのホスト側のインタフェース名を、
  nftablesの`iifname`や`networking.firewall.interfaces`で使える形で持つ読み取り専用の値。

  nspawnはvethを`ve-<コンテナ名>`と名付けるが、
  Linuxのインタフェース名はIFNAMSIZの制限で15文字までしか持てない。
  収まらない名前はsystemdの`shorten_ifname`が先頭11文字を残して、
  元の名前のハッシュから作った4文字を足した名前に縮める。
  実機では`ve-niks3-private`が`ve-niks3-preMOW`になっている。

  縮めた後の4文字はNixから再現できないので、
  先頭11文字にワイルドカードを付けた形にする。
  元の名前はaltnameとして残っていてsystemd-networkdの`matchConfig.Name`は拾えるが、
  nftablesの`iifname`は主名しか見ないため、
  firewallの側ではこの形でなければ何にも一致しない。

  同じ11文字を共有するコンテナは同じパターンに一致する。
  パターンでfirewallを開ける時はその全てに開くことになるので、
  使う側はそれで良いかを確かめること。

  # `local.serviceUser`

  `serviceUser.<name>`のIDで、コンテナと同じ名前のユーザとグループを、
  ホストとコンテナの両方に作る。
  ephemeralなコンテナでは動的に割り当てたIDの記録が起動ごとに消えるので、
  bind mountしたディレクトリの所有権がずれないようにIDを固定する。
  ホスト側にも作るのは、その所有者をホストから名前で扱うため。

  `local.persist`のように所有者になるユーザを必要とする宣言は、これを自動で有効にする。
  直接書くのは、それらを使わずにユーザだけが要る時に限る。

  # `local.persist`

  コンテナの再作成をまたいで残すディレクトリ。
  ホストとコンテナで同じパスになる。
  ホスト側に`0750`でサービスユーザの所有として用意して、コンテナへ読み書きできる形で渡す。

  コンテナの中のサービスがそのディレクトリをStateDirectoryにしていると、
  モードは起動ごとにsystemdが強制する。
  既定の`0755`のままだと、ブート直後とサービスの起動後でモードが変わるので、
  サービスの`StateDirectoryMode`も`0750`にする。

  `pick`では素のbind mountだと所有者が無効なUIDに見えて書き込めないので、
  idmapで数値のIDをホストとコンテナで同一視させる。
  `bindMounts`はマウントオプションを渡せないので`extraFlags`で渡す。
  `extraFlags`のbind mountには`bindMounts`と違って`RequiresMountsFor`が自動で付かないので、
  それもここで足す。
*/
{
  lib,
  pkgs,
  config,
  ...
}:
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
  # nixpkgsのコンテナのモジュールが`postStart`でホスト側のvethを設定するのと同じ条件。
  # ブリッジに繋ぐvethはアドレスを持たない。
  hasVethAddress =
    c:
    c.hostBridge == null
    && lib.any (address: address != null) [
      c.hostAddress6
      c.localAddress6
      c.hostAddress
      c.localAddress
    ];
  withVeth = lib.filterAttrs (_: hasVethAddress) config.containers;
  # vethは1対1なので、相手だけを指すプレフィックス長にする。
  # nixpkgsのオプションはプレフィックス長を付けた形も受け付けるので外す。
  hostPrefix =
    length: address:
    lib.optional (address != null) "${lib.head (lib.splitString "/" address)}/${toString length}";
  hostInterfaceOf =
    name:
    let
      full = "ve-${name}";
      # IFNAMSIZは終端のNULを含めて16なので、名前として使えるのは15文字まで。
      maxLength = 15;
      # 縮める時に残る先頭の長さ。15文字からハッシュの4文字を引いた11。
      keptLength = maxLength - 4;
    in
    if lib.stringLength full <= maxLength then full else "${lib.substring 0 keptLength full}*";
in
assert hostInterfaceOf "open-webui" == "ve-open-webui";
# ちょうど15文字の名前は縮められない。
assert hostInterfaceOf "niks3-public" == "ve-niks3-public";
assert hostInterfaceOf "niks3-private" == "ve-niks3-pr*";
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
            hostInterface = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = hostInterfaceOf name;
              defaultText = lib.literalMD "コンテナ名から導いたvethの名前。15文字に収まらない名前は先頭11文字と`*`";
              description = ''
                vethのホスト側のインタフェース名。
                nftablesの`iifname`や`networking.firewall.interfaces`に渡せる形で、
                末尾が`*`のワイルドカードになることがある。
              '';
            };
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
              # 残すディレクトリには所有者になるユーザが要る。
              local.serviceUser = lib.mkIf (cfg.persist != [ ]) true;
              config = {
                nixpkgs.pkgs = pkgs;
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
    assertions = lib.mapAttrsToList (name: c: {
      assertion = c.extraVeths == { };
      message = "containers.${name}.extraVeths: ホスト側のvethをsystemd-networkdで設定するために`postStart`を空にしているので、`extraVeths`は設定されません";
    }) withVeth;

    users = {
      users = lib.mapAttrs (name: _: userOf name) withServiceUser;
      groups = lib.mapAttrs (name: _: { inherit (idsOf name) gid; }) withServiceUser;
    };

    systemd = {
      network = lib.mkIf (withVeth != { }) {
        enable = true;
        networks = lib.mapAttrs' (
          name: c:
          lib.nameValuePair "20-${name}-veth" {
            matchConfig.Name = "ve-${name}";
            # 相手のコンテナが起動するまで設定が終わらない内向きのリンクなので、
            # ホストがオンラインかどうかの判定には含めない。
            linkConfig.RequiredForOnline = "no";
            addresses = map (Address: { inherit Address; }) (
              hostPrefix 128 c.hostAddress6 ++ hostPrefix 32 c.hostAddress
            );
            routes = map (Destination: { inherit Destination; }) (
              hostPrefix 128 c.localAddress6 ++ hostPrefix 32 c.localAddress
            );
          }
        ) withVeth;
      };
      tmpfiles.rules = lib.concatLists (
        lib.mapAttrsToList (
          name: c: map (path: "d ${path} 0750 ${name} ${name} -") c.local.persist
        ) withPersist
      );
      services = lib.mkMerge [
        (lib.mapAttrs' (
          name: c: lib.nameValuePair "container@${name}" { unitConfig.RequiresMountsFor = c.local.persist; }
        ) (lib.filterAttrs (_: usesIdmap) withPersist))
        (lib.mapAttrs' (
          name: _: lib.nameValuePair "container@${name}" { postStart = lib.mkForce ""; }
        ) withVeth)
      ];
    };
  };
}
