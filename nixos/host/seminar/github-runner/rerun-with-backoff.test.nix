# `rerun-with-backoff.nix`が、成功で終わったサービスをすぐ起動し直して、
# 失敗が続く時だけ間隔を伸ばすことを確認します。
#
# ランナのVMは秘密情報が無いとテストVMでは起動しないので、
# 決まった順に成功と失敗を返すサービスを対象にして、起動した時刻の間隔を見ます。
# ランナはジョブを終えるたびにこの経路で登録し直すので、
# 成功の後に起動し直されなくなると、ジョブを1つ終えた所でランナが居なくなります。
{ testers }:
testers.runNixOSTest {
  name = "rerun-with-backoff";

  containers.machine =
    { pkgs, ... }:
    {
      imports = [ ./rerun-with-backoff.nix ];
      local.rerunWithBackoff = [ "flaky" ];
      systemd.services.flaky = {
        serviceConfig = {
          StateDirectory = "flaky";
          # 起動した回数に応じて、失敗、失敗、1秒動いて成功、失敗の順に終わり、5回目からは動き続けます。
          # 起動した時刻を1行ずつ記録します。
          ExecStart = pkgs.writeShellScript "flaky" ''
            count=$(wc -l < "$STATE_DIRECTORY/starts" 2>/dev/null || echo 0)
            date +%s.%N >> "$STATE_DIRECTORY/starts"
            case "$count" in
              0 | 1 | 3) exit 1 ;;
              2) sleep 1 ;;
              *) sleep infinity ;;
            esac
          '';
        };
      };
    };

  testScript = # python
    ''
      machine.wait_for_unit("multi-user.target")
      machine.succeed("systemctl start --no-block flaky.service")
      machine.wait_until_succeeds("test $(wc -l < /var/lib/flaky/starts) -ge 5", timeout=120)
      starts = [float(line) for line in machine.succeed("cat /var/lib/flaky/starts").split()]
      intervals = [later - earlier for earlier, later in zip(starts, starts[1:])]

      with subtest("失敗が続くと間隔が伸びる"):
          assert 4 < intervals[0] < 10, intervals
          assert 10 < intervals[1] < 25, intervals

      with subtest("成功で終わるとすぐ起動し直される"):
          # 1秒動いてから成功で終わるので、間隔には動いていた1秒が入ります。
          assert intervals[2] < 4, intervals

      with subtest("成功の後の失敗は最短の間隔から始まる"):
          assert 4 < intervals[3] < 10, intervals

      with subtest("動き続けている間は起動し直されない"):
          machine.succeed("systemctl is-active flaky.service")
          assert machine.succeed("wc -l < /var/lib/flaky/starts").strip() == "5"

      # シャットダウンで止められた時にも`OnSuccess=`は呼ばれます。
      # そこで起動し直すと、ランナのVMが止まるのを待つホストのGCが進まなくなります。
      with subtest("シャットダウンは起動し直しに邪魔されずに終わる"):
          machine.shutdown()
    '';
}
