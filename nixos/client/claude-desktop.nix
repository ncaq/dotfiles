{ inputs, username, ... }:
{
  imports = [ inputs.claude-desktop.nixosModules.default ];

  programs.claude-desktop = {
    enable = true;
    # Coworkのmicro-VMは`/dev/kvm`を開く必要があるため、
    # 上流モジュールにkvmグループへ追加するユーザを渡す。
    cowork.kvmUsers = [ username ];
  };
}
