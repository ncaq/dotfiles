{ lib, pkgs, ... }:
let
  # 他のSSDに入っているWindows環境の一覧。
  # Limineのメニューエントリ名とESPパーティションのGPT PARTUUIDの対応。
  windows = {
    game = {
      entryName = "Windows Game";
      espPartUuid = "4df43761-322e-44ef-9219-3b923e95d5b6";
    };
    work = {
      entryName = "Windows Work";
      espPartUuid = "386d2f0a-f36e-4678-93d1-84c7df8665a0";
    };
  };
  # 次回起動時だけ指定のWindowsを起動するように設定して再起動するコマンド。
  # LimineはsystemdのBoot Loader Interfaceのone-shot entry指定に対応しているため、
  # `bootctl set-oneshot`でEFI変数`LoaderEntryOneShot`にエントリのツリーパスを書き込むと、
  # Limineが次回起動時に一度だけそのエントリを自動選択します。
  mkRebWindows =
    name:
    { entryName, ... }:
    pkgs.writeShellApplication {
      name = "reb-windows-${name}";
      runtimeInputs = with pkgs; [
        systemd
      ];
      text = ''
        bootctl set-oneshot ${lib.escapeShellArg entryName}
        systemctl reboot
      '';
    };
in
{
  boot = {
    loader = {
      limine = {
        # 他のSSDに入っているWindowsのブートマネージャにチェインロードします。
        # vfatのボリュームシリアルはGUID形式ではないため、
        # GPTパーティションGUID(PARTUUID)で指定します。
        extraEntries = lib.concatMapAttrsStringSep "\n" (
          _:
          { entryName, espPartUuid }:
          ''
            /${entryName}
                protocol: efi_chainload
                path: guid(${espPartUuid}):/EFI/Microsoft/Boot/bootmgfw.efi
          ''
        ) windows;
      };
    };
  };

  environment.systemPackages = lib.mapAttrsToList mkRebWindows windows;
}
