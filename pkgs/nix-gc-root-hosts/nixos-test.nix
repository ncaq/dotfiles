# GC rootの更新(`module.nix`)が、ストアのGCの前に意図した形で挟まっていることを確認します。
# 崩れても評価とブートは通り、
# GC rootが更新されなくなったり、GCが動かなくなったりするだけなので、気付きにくいです。
#
# systemd-nspawnのコンテナの中で`module.nix`の実際のユニットを読み込んで確かめます。
# ホストの構成には依らないので、ホストをブートするテストではなくここに置いています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 以下を見ます。
#
# - GCのタイマーが、GCではなくGC rootの更新を起動すること
# - GC rootの更新が終わった時に、終わりを待たずにGCを起動すること
# - GC rootの更新にも、負荷の検査と再試行の打ち切りが入っていること
#
# 本体は全ホストの構成をビルドするものなので、ここでは動かしません。
# 本体の振る舞いはsandwichのテスト(`test`)で見ています。
{ localLib, testers }:
testers.runNixOSTest {
  name = "nix-gc-root-hosts";

  node.specialArgs.hardening = localLib.hardening;

  containers.machine = {
    imports = [ ./module.nix ];
  };

  testScript = # python
    ''
      def unit_lines(unit, key):
          text = machine.succeed(f"systemctl cat {unit}")
          return [
              line.split("=", 1)[1].strip()
              for line in text.splitlines()
              if line.startswith(key + "=")
          ]

      machine.wait_for_unit("multi-user.target")

      gc_timer_unit = machine.succeed(
          "systemctl show nix-gc.timer --property=Unit --value"
      ).strip()
      assert gc_timer_unit == "nix-gc-root-hosts.service", gc_timer_unit

      start_post = unit_lines("nix-gc-root-hosts.service", "ExecStartPost")
      assert len(start_post) == 1, start_post
      assert start_post[0].endswith("start --no-block nix-gc.service"), start_post

      start_pre = unit_lines("nix-gc-root-hosts.service", "ExecStartPre")
      assert len(start_pre) == 1, start_pre
      assert "nix-store-maintenance-condition" in start_pre[0], start_pre
      condition = unit_lines("nix-gc-root-hosts.service", "ExecCondition")
      assert len(condition) == 1, condition
      assert "nix-store-maintenance-retry-limit" in condition[0], condition
    '';
}
