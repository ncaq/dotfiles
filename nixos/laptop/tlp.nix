# ラップトップの電源管理ツールのtlpの設定をします。
# [NixOS/nixos-hardware](https://github.com/NixOS/nixos-hardware)
# でラップトップたちはtlpをデフォルトで有効にされています。
# しかしデフォルト設定がどれを選択しているのかイマイチわかりにくいので、
# 念の為ユーザレベルでも設定しています。
_: {
  services = {
    tlp = {
      enable = true;
      settings = {
        # CPU動作モードを明示。
        # amd-pstateを想定しています。
        # kernelが自動で`active`を選びますが念の為設定しています。
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";

        # ガバナーも明示。
        # amd-pstateのactive modeでは`powersave`一択。
        # `performance`は無意味に発熱します。
        # 負荷が高いときはCPUが自律的に周波数を上げるので、
        # 性能が犠牲になることはありません。
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        # EPPはデフォルトでは`balance_performance`/`balance_power`になります。
        # AC接続時は性能を重視したいので、
        # デフォルト値の`balance_performance`を念の為明示的に設定します。
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
        # バッテリー時は電力を更に重視したいので、
        # `balance_power`から`power`に変更します。
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      };
    };
  };
}
