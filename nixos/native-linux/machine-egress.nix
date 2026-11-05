/**
  コンテナとmicroVMからの転送を、マシンごとに宣言した宛先だけに絞る。

  NATモジュールは`internalInterfaces`からの転送を無条件に通すので、
  何も書かないとコンテナの中のコードは自宅LANにもtailnetにも他のコンテナにも届く。
  コンテナの中で動くのはCIが持ち込んだコードやブラウザから渡したURLを開くWeb UIで、
  どれも宛先を信用する理由が無い。

  マシンごとに`local.machineEgress.<name>`で許す宛先を宣言し、
  それ以外は落とす。
  宣言が無いマシンは何も許されない。
  ネットワークを持つコンテナとmicroVMは全て宣言を要求するので、
  新しく足した時に黙って全開のまま動くことも、
  黙って不通のまま動くことも無い。

  # 転送しか見ない

  ここで絞るのはforwardフック、
  つまりコンテナから外(インターネット、LAN、tailnet、他のコンテナ)へ向かう経路だけ。
  ホスト自身のサービス(vethのホスト側アドレスのCaddyなど)へはinputフックで届くので、
  そちらは`networking.firewall.interfaces.<veth>`で開ける。
  ホストからコンテナへの接続はoutputフックで、これも対象外。

  # 独立したテーブルにしている理由

  NixOSのfirewallの`extraForwardRules`ではなく専用のテーブルにしているのは、
  nixos-fwのforward-allowチェインの中での並び順に依存しないため。
  あちらでは`ct status dnat accept`がどのルールよりも先に評価されるので、
  DNATされたポート(forgejoの2222など)への転送はdropを素通りするし、
  NATモジュールの`internalInterfaces`のacceptより前に並ぶことも`mkBefore`の順序に頼ることになる。
  nftablesでは同じフックの全てのベースチェインを通る必要があり、
  どこか1つのチェインでdropされたパケットは他のチェインがacceptしていても落ちる。
  独立したベースチェインに置けば、
  nixos-fwやnixos-natの中身がどう並んでいても必ず評価される。
  priorityを`filter - 1`にしてnixos-fwより先に評価させるのは、
  dropが決まっているパケットに他のチェインの評価を費やさないため。

  送信元アドレスではなくインターフェイス名で見るのは、
  コンテナのrootは自分のnetns内で任意の送信元アドレスを名乗れるため。

  # IPv6

  コンテナとmicroVMにはULA(`lib/machine-address6.nix`)が付いていて、
  NATモジュールの`enableIPv6`でmasqueradeされて外へ出る。
  IPv4の`private-networks`に当たる集合はIPv6では`private-networks6`で、
  tailnetと他のコンテナを含むULA全体とリンクローカルが入る。

  自宅LANの機器が持つグローバルなIPv6アドレスは、
  IPv4の192.168.0.0/16のような固定の範囲では表せない。
  LANの/64はルータのRAで配られる動的な値で、
  ここへ書き写すと変わった時に静かに穴が開く。
  代わりに経路のnexthopで見分ける。
  インターネット宛の転送はルータのリンクローカルアドレスをnexthopに持ち、
  同じリンクにいるLAN機器宛の転送はその機器自身のアドレスがnexthopになる。
  `rt ip6 nexthop fe80::/10`で前者だけを通せば、
  LANの/64が何であってもLAN機器へは届かない。

  この判定はホストの経路表に前提を置いていて、
  崩れた時は許可側に倒れる。

  - LANの/64がon-linkの経路として載っていること。
    ルータのRAのPrefix InformationでLフラグが立っていれば載る。
    Lフラグが0のRAや、DHCPv6だけでアドレスを得る構成では載らず、
    LAN機器宛もルータのリンクローカルがnexthopになってこのルールを通る。
    前提が崩れたかは`ip -6 route`に`proto ra`の/64があるかで分かる。
  - 自宅LANが1つのセグメントであること。
    IPv4の`192.168.0.0/16`はルータ越しの別セグメントも含めて落とすが、
    IPv6ではルータの先にある別セグメントやルータの別インターフェイスのグローバルアドレスは、
    インターネット宛と区別が付かず通る。
    今の自宅LANにそのような宛先は無い。

  ルータ役とLAN役を立てる多ノードのVMテストで振る舞いを固定することは見送った。
  確かめたいのはカーネルの`rt nexthop`がon-linkの宛先で自身を返すことで、
  そのためだけにテストのトポロジを組む費用に見合わない。
  ブートテストはルールの形だけを見る。

  `destinations`で個別に許す宛先は同じホスト上の他のマシンで、
  そちらへはIPv4で繋いでいるのでIPv6の宛先は受け付けない。
*/
{ lib, config, ... }:
let
  cfg = config.local.machineEgress;
  tailscale = config.local.tailscale;

  # 宣言を名前付きのリストにして、インターフェイスのパターンごとにまとめる。
  # `lib/container-ifname.nix`のワイルドカードで複数のコンテナが同じパターンに一致する時、
  # マシンごとにルールを並べると先のマシンのdropで後のマシンのacceptが届かなくなる。
  # 同じパターンのマシンは同じ方針でなければならない(assertionで検査する)ので、
  # パターンごとに1組だけ出す。
  machines = lib.mapAttrsToList (name: m: m // { inherit name; }) cfg;
  byInterface = lib.groupBy (m: m.interface) machines;
  policyOf = m: {
    inherit (m) internet destinations;
  };
  conflictingInterfaces = lib.filterAttrs (
    _: group: lib.length (lib.unique (map policyOf group)) > 1
  ) byInterface;

  # 宣言を要求するマシンの一覧。
  # アドレスを持たないコンテナ(postgresqlなど)はそもそも転送されるパケットを出せないので要求しない。
  # microVMのホストモジュールを取り込んでいないホストでは`config.microvm`自体が無い。
  networkedContainers = lib.attrNames (
    lib.filterAttrs (_: c: c.localAddress != null) config.containers
  );
  vms = lib.attrNames (config.microvm.vms or { });
  expected = networkedContainers ++ vms;
  undeclared = lib.subtractLists (lib.attrNames cfg) expected;
  unknown = lib.subtractLists expected (lib.attrNames cfg);

  # NATモジュールが転送を通すインターフェイスの集合。
  # ベースチェインでこの集合からのパケットだけを許可リストへ回すので、
  # 宣言したインターフェイスがこの集合に入っていなければ許可リストは評価すらされない。
  internalInterfaces = config.networking.nat.internalInterfaces;
  matchesPattern =
    pattern: ifname:
    if lib.hasSuffix "*" pattern then
      lib.hasPrefix (lib.removeSuffix "*" pattern) ifname
    else
      pattern == ifname;
  uncovered = lib.filter (
    m: !(lib.any (pattern: matchesPattern pattern m.interface) internalInterfaces)
  ) machines;

  nftSet = list: lib.concatMapStringsSep ", " (x: ''"${x}"'') list;

  # インターフェイスのパターン1つ分のルールの行のリスト。
  renderGroup =
    group:
    let
      names = lib.concatMapStringsSep ", " (m: m.name) group;
      m = lib.head group;
      match = ''iifname "${m.interface}"'';
    in
    map (
      d:
      ''${match} ip daddr ${d.address} tcp dport { ${
        lib.concatMapStringsSep ", " toString d.tcpPorts
      } } accept comment "${names}: to ${d.address}"''
    ) m.destinations
    ++ lib.optionals m.internet [
      ''${match} ip daddr != @private-networks accept comment "${names}: internet"''
      ''${match} ip6 daddr != @private-networks6 rt ip6 nexthop fe80::/10 accept comment "${names}: internet (IPv6)"''
    ]
    ++ [ ''${match} counter drop comment "${names}: everything else"'' ];
  egressRules = lib.concatMap renderGroup (lib.attrValues byInterface);
in
{
  options.local.machineEgress = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            interface = lib.mkOption {
              type = lib.types.str;
              default = import ../../lib/container-ifname.nix { inherit lib name; };
              defaultText = lib.literalMD "`lib/container-ifname.nix`でコンテナ名から導いたvethの名前";
              description = ''
                このマシンからのパケットが入ってくるホスト側のインターフェイス名。
                nftablesの`iifname`に渡すので末尾の`*`でワイルドカードにできる。
                コンテナはvethの名前が既定で導けるが、
                microVMはTAPの名前を`microvm.vms.<name>.config.microvm.interfaces`で決めているので、
                そちらと同じ値を明示する。
              '';
            };
            internet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                プライベートでないIPv4アドレスと、
                ルータ越しにしか届かないIPv6アドレスへの転送を許すか。
                自宅LAN、tailnet、他のコンテナ、リンクローカルは含まない。
                名前解決もこの経路を使う。
                コンテナのsystemd-resolvedはDNSサーバを教わらないのでフォールバックの公開DNSへ問い合わせるため、
                これを許さないマシンは名前を引けない。
              '';
            };
            destinations = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    address = lib.mkOption {
                      type = lib.types.str;
                      description = "許す宛先のIPv4アドレス。他のマシンのゲスト側アドレスなど。";
                    };
                    tcpPorts = lib.mkOption {
                      type = lib.types.nonEmptyListOf lib.types.port;
                      description = "その宛先で許すTCPポート。";
                    };
                  };
                }
              );
              default = [ ];
              description = ''
                `internet`の範囲外で個別に許す宛先。
                同じホスト上の他のマシンへ繋ぐ時に使う。
              '';
            };
          };
        }
      )
    );
    default = { };
    description = ''
      コンテナとmicroVMからの転送の許可リスト。
      属性名はコンテナ名かmicroVM名で、書いていない宛先への転送は落ちる。
      ネットワークを持つコンテナとmicroVMは全てここに書く必要がある。
    '';
  };

  config = {
    # 宣言が1つも無いホストでもコンテナがあれば検査は走らせる。
    # テーブルの生成だけを宣言の有無で切ると、
    # 宣言を全て消した時に検査ごと消えて全開のまま通ってしまう。
    networking.nftables.tables.machine-egress = lib.mkIf (cfg != { }) {
      family = "inet";
      content = ''
        # `internet`で許さない範囲。
        # RFC 1918の各範囲とtailnetのCGNAT空間とリンクローカル。
        # 自宅LANと他のコンテナのアドレスは192.168.0.0/16に含まれる。
        set private-networks {
          type ipv4_addr
          flags interval
          elements = {
            10.0.0.0/8,
            172.16.0.0/12,
            192.168.0.0/16,
            ${tailscale.ipv4Range},
            169.254.0.0/16
          }
        }

        # IPv6で`internet`で許さない範囲。
        # ULA全体(tailnetの${tailscale.ipv6Range}と他のコンテナを含む)とリンクローカル。
        # 自宅LANのグローバルなアドレスはここには書けないので、
        # 許可ルール側でnexthopがルータかどうかを見る。
        set private-networks6 {
          type ipv6_addr
          flags interval
          elements = {
            fc00::/7,
            fe80::/10
          }
        }

        chain forward {
          type filter hook forward priority filter - 1; policy accept;
          iifname { ${nftSet (lib.unique internalInterfaces)} } jump egress
        }

        chain egress {
          # 許した接続の続きと、LANからDNATされてコンテナへ届いた接続の戻りを通す。
          ct state { established, related } accept

          ${lib.concatStringsSep "\n  " egressRules}

          counter drop comment "undeclared machine"
        }
      '';
    };

    assertions = [
      {
        assertion = undeclared == [ ];
        message = "local.machineEgress: ネットワークを持つコンテナとmicroVMは全て出口の方針を宣言する必要があります。未宣言: ${lib.concatStringsSep ", " undeclared}";
      }
      {
        assertion = unknown == [ ];
        message = "local.machineEgress: 存在しないマシンが宣言されています: ${lib.concatStringsSep ", " unknown}";
      }
      {
        assertion = conflictingInterfaces == { };
        message = "local.machineEgress: 同じインターフェイスのパターンに一致するマシンの方針が食い違っています: ${
          lib.concatStringsSep "; " (
            lib.mapAttrsToList (
              iface: group: "${iface} (${lib.concatMapStringsSep ", " (m: m.name) group})"
            ) conflictingInterfaces
          )
        }";
      }
      {
        assertion = uncovered == [ ];
        message = "local.machineEgress: networking.nat.internalInterfacesに含まれないインターフェイスは許可リストが評価されません: ${
          lib.concatMapStringsSep ", " (m: "${m.name} (${m.interface})") uncovered
        }";
      }
    ];
  };
}
