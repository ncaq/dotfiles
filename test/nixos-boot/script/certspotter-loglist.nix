# certspotterへ渡すCTログの一覧から、追従できないログだけが除かれることを確認します。
# 一覧は上流から取得して加工するので、評価とブートが通っても、
# 加工が壊れて全部のログを落としたり何も除かなかったりすることには気付けません。
# 監視するログが黙って減ると、証明書の発行を見逃します。
#
# テストVMはネットワークに繋がっていないので、
# 取得元を手元のファイルに差し替えて、実機と同じ更新のスクリプトを実行します。
#
# certspotterを動かしていないホストには更新のサービスが無いので、空文字列を返します。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  service = config.systemd.services.certspotter-loglist or null;
  # certspotterが読む一覧のパス。`-logs`の次の引数である。
  logListFile =
    let
      flags = config.services.certspotter.extraFlags;
    in
    (lib.findFirst (pair: pair.fst == "-logs") null (lib.zipLists flags (lib.tail flags))).snd;
  # 上流の一覧と同じ形で、除く対象のe-szignoと残す対象を混ぜたもの。
  # e-szignoだけを持つ運営者も、RFC 6962のログ(`logs`)しか持たない運営者も含める。
  upstream = pkgs.writeText "certspotter-loglist-upstream.json" (
    builtins.toJSON {
      version = "1.0";
      operators = [
        {
          name = "kept and dropped";
          tiled_logs = [
            {
              description = "Microsec e-szigno 2027h1";
              log_id = "drop-tiled";
              monitoring_url = "https://eszigno2027h1.mon.ct.e-szigno.hu/";
              submission_url = "https://eszigno2027h1.log.ct.e-szigno.hu/";
            }
            {
              description = "kept tiled";
              log_id = "keep-tiled";
              monitoring_url = "https://mon.example.com/2027h1/";
              submission_url = "https://log.example.com/2027h1/";
            }
            {
              # ドメインの末尾が似ているだけのログは除かない。
              description = "kept lookalike";
              log_id = "keep-lookalike";
              monitoring_url = "https://mon.not-ct.e-szigno.hu.example.com/";
              submission_url = "https://log.not-ct.e-szigno.hu.example.com/";
            }
          ];
          logs = [
            {
              description = "kept rfc6962";
              log_id = "keep-rfc6962";
              url = "https://ct.example.com/logs/2027/";
            }
          ];
        }
        {
          name = "rfc6962 only";
          logs = [
            {
              description = "dropped rfc6962";
              log_id = "drop-rfc6962";
              url = "https://old.ct.e-szigno.hu/log/";
            }
          ];
        }
      ];
    }
  );
  # 加工すると監視するログが1つも残らない一覧。
  onlyDropped = pkgs.writeText "certspotter-loglist-only-dropped.json" (
    builtins.toJSON {
      version = "1.0";
      operators = [
        {
          name = "dropped";
          tiled_logs = [
            {
              description = "Microsec e-szigno 2027h1";
              log_id = "drop-tiled";
              monitoring_url = "https://eszigno2027h1.mon.ct.e-szigno.hu/";
              submission_url = "https://eszigno2027h1.log.ct.e-szigno.hu/";
            }
          ];
        }
      ];
    }
  );
in
lib.optionalString (service != null) # python
  ''
    import json

    loglist_dir = "/tmp/certspotter-loglist-test"
    loglist_update = ${builtins.toJSON service.serviceConfig.ExecStart}
    loglist_file = f"{loglist_dir}/${baseNameOf logListFile}"


    def loglist_run(url):
        return (
            f"STATE_DIRECTORY={loglist_dir} CERTSPOTTER_LOGLIST_URL=file://{url} {loglist_update}"
        )


    def loglist_ids():
        loglist = json.loads(machine.succeed(f"cat {loglist_file}"))
        return sorted(
            log["log_id"]
            for operator in loglist["operators"]
            for key in ["logs", "tiled_logs"]
            for log in operator.get(key) or []
        )


    machine.succeed(f"mkdir -p {loglist_dir}")
    machine.succeed(loglist_run("${upstream}"))
    kept = ["keep-lookalike", "keep-rfc6962", "keep-tiled"]
    assert loglist_ids() == kept, loglist_ids()

    # 監視するログが1つも残らない一覧は置かずに失敗して、前の一覧を残す。
    machine.fail(loglist_run("${onlyDropped}"))
    assert loglist_ids() == kept, loglist_ids()
    # 壊れた一覧も同じ。
    machine.succeed("echo 'not json' > /tmp/certspotter-loglist-broken.json")
    machine.fail(loglist_run("/tmp/certspotter-loglist-broken.json"))
    assert loglist_ids() == kept, loglist_ids()
    # 作りかけのファイルを残さない。
    leftovers = machine.succeed(f"ls -A {loglist_dir}").split()
    assert leftovers == ["${baseNameOf logListFile}"], leftovers

    # certspotterがその一覧を読むこと。
    certspotter_unit = machine.succeed("systemctl cat certspotter.service")
    certspotter_start = [
        line.split("=", 1)[1].strip()
        for line in certspotter_unit.splitlines()
        if line.startswith("ExecStart=")
    ]
    assert len(certspotter_start) == 1, certspotter_unit
    certspotter_script = machine.succeed(f"cat {certspotter_start[0]}")
    assert "-logs ${logListFile}" in certspotter_script, certspotter_script
  ''
