{
  pkgs,
  lib,
  ...
}:
let
  # certspotterのhookが検知したイベントを1行ずつ追記するログ。
  # `$CERTSPOTTER_STATE_DIR`は`/var/lib/certspotter`で、
  # hookはcertspotterの環境変数を引き継ぐのでhook側はそちらで参照します。
  eventsLog = "/var/lib/certspotter/events.log";
  # この時間以内のイベントがあればMackerelのチェックをCRITICALにします。
  # アラートが一定期間開いたままになることで見落としを防ぎます。
  alertWindowSeconds = 24 * 60 * 60;
in
{
  # Certificate Transparencyログを監視して、
  # ncaq.net向けに発行された証明書を全て検知します。
  #
  # CAAレコードは真面目なCAの誤発行を防ぐだけで、
  # 秘密鍵が漏洩した中間CAによる発行(2026年10月のeMudhraの事件など)には無力です。
  # そのような発行はドメイン側で防げないので、
  # 代わりにCTログで検知して気づけるようにします。
  #
  # 発行元によるフィルタはしません。
  # ncaq.netの証明書はCloudflare Universal SSLとlegoの更新くらいで数が少なく、
  # 全件を目で見たほうが見落としが無いためです。
  services.certspotter = {
    enable = true;
    # 先頭の`.`でncaq.net自身と全てのサブドメインを対象にします。
    watchlist = [ ".ncaq.net" ];
    hooks = [
      (lib.getExe (
        pkgs.writeShellApplication {
          name = "certspotter-hook";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
          ];
          # 環境変数の仕様は`man 8 certspotter-script`を参照。
          # `discovered_cert`以外(`malformed_cert`, `error`)も監視自体の異常なので記録します。
          text = ''
            dns_names=""
            if [[ "''${EVENT:-}" == "discovered_cert" && -n "''${JSON_FILENAME:-}" ]]; then
              dns_names=$(jq -r '.dns_names | join(",")' "$JSON_FILENAME")
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' \
              "$(date +%s)" \
              "''${EVENT:-unknown}" \
              "''${SUMMARY:-}" \
              "$dns_names" \
              "''${ISSUER_DN:-}" \
              >>"$CERTSPOTTER_STATE_DIR/events.log"
          '';
        }
      ))
    ];
  };

  # 検知したイベントは既存のMackerelの通知経路に乗せます。
  # mackerel-agentはrootで動くのでcertspotterのstateディレクトリを直接読めます。
  services.mackerel-agent.settings.plugin.checks.certspotter = {
    command = lib.getExe (
      pkgs.writeShellApplication {
        name = "check-certspotter";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.systemd
        ];
        text = ''
          if ! systemctl is-active --quiet certspotter.service; then
            echo "certspotter CRITICAL: service not running"
            exit 2
          fi
          if [[ ! -f ${eventsLog} ]]; then
            echo "certspotter OK (no events yet)"
            exit 0
          fi
          threshold=$(( $(date +%s) - ${toString alertWindowSeconds} ))
          recent=$(awk -F '\t' -v threshold="$threshold" '
            $1 >= threshold {
              printf "%s %s: %s (%s) issuer=%s\n", strftime("%Y-%m-%dT%H:%M:%S%z", $1), $2, $3, $4, $5
            }
          ' ${eventsLog})
          if [[ -n "$recent" ]]; then
            echo "certspotter CRITICAL: new certificate transparency events"
            echo "$recent"
            exit 2
          fi
          echo "certspotter OK"
          exit 0
        '';
      }
    );
    check_interval = 3;
    # イベントは一定期間残るので連続失敗の判定を待つ意味がなく、
    # すぐに通知を出します。
    max_check_attempts = 1;
  };
}
