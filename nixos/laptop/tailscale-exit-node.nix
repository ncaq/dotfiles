{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.custom.tailscale-exit-node;
  # tailscale pingのレイテンシでローカルネットワークにいるかを判定し、
  # exit nodeの設定を切り替えるスクリプト。
  # 中身は`pkgs/tailscale-exit-node`にあります。
  tailscaleExitNodeScript = lib.getExe (
    pkgs.callPackage ../../pkgs/tailscale-exit-node {
      tailscale = config.services.tailscale.package;
    }
  );
in
{
  options.custom.tailscale-exit-node.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      自動的にTailscaleのexit nodeを切り替えます。

      外出時はexit nodeをseminarにします。
      ただしseminarと同じローカルネットワークにいる場合は無駄なので通常の通信を行います。

      一応あまり信頼できないネットワーク上でも多重に暗号化をかけることが出来ます。
      普通は今どきTLSなどアプリケーション側で既に暗号化されているはずですが。

      差し迫ったセキュリティ要件が自分にあるわけではないので、
      ローカルネットワークの判定はかなり雑にレイテンシで行っています。
      WIFIのSSIDとかMACアドレスとかはそれはそれで偽装可能なので行っていません。
      真面目にやるとしたらサーバの認証機構などを作るべきでしょうが、
      現在はそこまですることでもないと判断しています。
    '';
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.dispatcherScripts = [
      {
        source = tailscaleExitNodeScript;
        type = "basic";
      }
    ];
  };
}
