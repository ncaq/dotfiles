# ホストのGCとストアの最適化の前後の処理に、
# 全てのGitHub ActionsのランナのVMのユニットが入っていることを確認します。
# GCがパスを消した後もVMが動き続けると、VMのデータベースと実体が食い違います。
# 最適化がファイルを置き換えた後もVMが動き続けると、VMの中でストアのファイルが開けなくなります。
#
# VMのユニットがGCと最適化の後に順序付けられていることも確認します。
# 順序が無いと、GCに続けて最適化が動く時に、
# VMがGCの後に起動しかけて、すぐ最適化の前処理に止められます。
#
# ランナのVMは秘密情報が無いとテストVMでは起動しないので、
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
    for store_unit in ["nix-gc.service", "nix-optimise.service"]:
        store_unit_text = machine.succeed(f"systemctl cat {store_unit}")
        for key in ["ExecStartPre", "ExecStopPost"]:
            store_unit_scripts = [
                line.split("=", 1)[1].strip()
                for line in store_unit_text.splitlines()
                if line.startswith(key + "=")
            ]
            # 負荷の検査のように、スクリプトではない実行ファイルが並ぶこともあります。
            # バイナリの中身はそのままでは読めないので、VMのユニットの名前だけを抜き出します。
            assert len(store_unit_scripts) >= 1, (store_unit, store_unit_text)
            store_unit_script = machine.succeed(
                "cat "
                + " ".join(store_unit_scripts)
                + " | grep --text --only-matching 'microvm@[A-Za-z0-9-]*[.]service' || true"
            )
            for unit in ${builtins.toJSON units}:
                assert unit in store_unit_script, (store_unit, key, unit, store_unit_script)
        for unit in ${builtins.toJSON units}:
            unit_after = machine.succeed(f"systemctl show {unit} --property=After --value").split()
            assert store_unit in unit_after, (store_unit, unit, unit_after)
  ''
