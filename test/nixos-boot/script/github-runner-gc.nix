# ホストのGCの前後の処理に、全てのGitHub ActionsのランナーのVMのユニットが入っていることを確認します。
# GCがパスを消した後もVMが動き続けると、VMのデータベースと実体が食い違います。
# ランナーのVMは秘密情報が無いとテストVMでは起動しないので、
# 評価とブートが通っても、
# ここが壊れたことには気付けません。
#
# `nixos/host/seminar/github-runner`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{ lib, config, ... }:
let
  githubRunnerVms = config.local.githubRunnerVms or { };
  units = map (name: "microvm@${name}.service") (lib.attrNames githubRunnerVms);
in
lib.optionalString (githubRunnerVms != { }) # python
  ''
    nix_gc_unit = machine.succeed("systemctl cat nix-gc.service")
    for key in ["ExecStartPre", "ExecStopPost"]:
        nix_gc_scripts = [
            line.split("=", 1)[1].strip()
            for line in nix_gc_unit.splitlines()
            if line.startswith(key + "=")
        ]
        assert len(nix_gc_scripts) == 1, nix_gc_unit
        nix_gc_script = machine.succeed(f"cat {nix_gc_scripts[0]}")
        for unit in ${builtins.toJSON units}:
            assert unit in nix_gc_script, (key, unit, nix_gc_script)
  ''
