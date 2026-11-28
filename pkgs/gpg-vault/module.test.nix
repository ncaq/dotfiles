# `module.nix`が入力に掛けている検査が、
# 誤った入力で落ちて、正しい入力では落ちないことを確かめる。
#
# 実機の入力は正しいので、
# 検査が働かなくなっても評価は通ったまま気付けない。
# `nixos-test.nix`も正しい入力でしかモジュールを動かさない。
# 以下を見る。
#
# - フィンガープリントとkeygripが、40桁の大文字の16進数だけを受け付けること
# - `users`に入れたユーザにlingerが無いと、そのユーザを名指しして止めること
#
# `module.nix`だけを`lib.evalModules`で読み込み、
# 参照している他のオプションは最小の形で用意する。
{ lib, localLib }:
let
  # ホストでは`specialArgs`から届く引数を、モジュールだけを読むここでも渡す。
  specialArgs = { inherit (localLib) hardening; };
  stub = {
    options = {
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
      users = {
        users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              freeformType = lib.types.attrsOf lib.types.anything;
              # NixOSと同じく、指定しなければ`null`になる。
              options.linger = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
              };
            }
          );
          default = { };
        };
        groups = lib.mkOption {
          type = lib.types.anything;
          default = { };
        };
      };
      # ユニットとtmpfilesの定義を受けるだけ。
      systemd = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
    };
    # 検査が読むのはソケットの場所だけ。
    config._module.args.pkgs.gpg-vault.socketDir = "/run/gpg-vault";
  };

  valid = "0123456789ABCDEF0123456789ABCDEF01234567";

  evaluate =
    settings:
    (lib.evalModules {
      inherit specialArgs;
      modules = [
        ./module.nix
        stub
        {
          services.gpg-vault = {
            enable = true;
            fingerprint = valid;
            sshKeygrip = valid;
          }
          // settings;
        }
      ];
    }).config;

  # フィンガープリントとkeygripのそれぞれに値を渡して、どちらも受け付けられるか。
  # 型に合わない値は、オプションの値を読んだ時に評価が止まる。
  accepts =
    value:
    lib.all (
      name: (builtins.tryEval (evaluate { ${name} = value; }).services.gpg-vault.${name}).success
    ) keyOptions;
  rejects =
    value:
    lib.all (
      name: !(builtins.tryEval (evaluate { ${name} = value; }).services.gpg-vault.${name}).success
    ) keyOptions;
  keyOptions = [
    "fingerprint"
    "sshKeygrip"
  ];

  # 落ちた検査のメッセージの一覧。
  failures =
    module:
    let
      evaluated = lib.evalModules {
        inherit specialArgs;
        modules = [
          ./module.nix
          stub
          {
            services.gpg-vault = {
              enable = true;
              fingerprint = valid;
              sshKeygrip = valid;
              users = [
                "alice"
                "bob"
              ];
            };
          }
          module
        ];
      };
    in
    map (a: a.message) (lib.filter (a: !a.assertion) evaluated.config.assertions);

  lingerMissing = failures { users.users.alice.linger = true; };
  lingerFalse = failures {
    users.users = {
      alice.linger = true;
      bob.linger = false;
    };
  };
  lingerAll = failures {
    users.users = {
      alice.linger = true;
      bob.linger = true;
    };
  };
  # 落ちた検査がちょうど1つで、bobを名指ししていてaliceには触れていないか。
  failsOnlyForBob =
    result:
    lib.length result == 1
    && lib.hasInfix "users.users.bob.linger" (lib.head result)
    && !lib.hasInfix "alice" (lib.head result);
in
assert lib.assertMsg (accepts valid) "40桁の大文字の16進数が受け付けられません";
assert lib.assertMsg (rejects (lib.toLower valid)) "小文字の16進数が受け付けられています";
assert lib.assertMsg (rejects "0123 4567 89AB CDEF 0123 4567 89AB CDEF 0123 4567")
  "空白の入った表記が受け付けられています";
assert lib.assertMsg (rejects "0123456789ABCDEF") "16桁の鍵IDが受け付けられています";
assert lib.assertMsg (rejects "${valid}0") "41桁の値が受け付けられています";
assert lib.assertMsg (failsOnlyForBob lingerMissing)
  "lingerを指定していないユーザだけが止められていません: ${lib.concatStringsSep ", " lingerMissing}";
assert lib.assertMsg (failsOnlyForBob lingerFalse)
  "lingerを切ったユーザだけが止められていません: ${lib.concatStringsSep ", " lingerFalse}";
assert lib.assertMsg (
  lingerAll == [ ]
) "全員にlingerがあるのに止められています: ${lib.concatStringsSep ", " lingerAll}";
true
