{
  lib,
  pkgs,
  config,
  isTermux,
  ...
}:
let
  cfg = config.programs.git-repo-subscribe;
  git-repo-subscribe = pkgs.callPackage ../pkgs/git-repo-subscribe { };

  # ここでは評価時の基本的な誤りだけを検出し、完全な入力検証は実行時のRust側で行います。
  gitRemoteType = lib.types.addCheck lib.types.str (
    url:
    builtins.match "^https://[^@/[:space:]]+(/[^[:space:]]*)?$" url != null
    || builtins.match "^file://([^@/[:space:]]+)?/[^[:space:]]*$" url != null
    || builtins.match "^ssh://([^:/@[:space:]]+@)?[^@[:space:]]+$" url != null
  );
  absolutePathType = lib.types.addCheck lib.types.str (
    path:
    let
      components = lib.drop 1 (lib.splitString "/" path);
    in
    lib.hasPrefix "/" path
    && components != [ ]
    && lib.all (component: component != "" && component != "." && component != "..") components
  );
  filterType = lib.types.addCheck lib.types.str (
    filter: filter != "" && builtins.match "^[^[:space:]]+$" filter != null
  );

  repositoryType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = gitRemoteType;
        description = "URL of the Git repository";
        example = "https://github.com/NixOS/nixpkgs.git";
      };

      path = lib.mkOption {
        type = absolutePathType;
        description = "Local worktree path";
        example = "/home/user/Desktop/nixpkgs";
      };

      partialCloneFilter = lib.mkOption {
        type = filterType;
        default = "blob:none";
        description = "Partial clone filter used for the initial clone";
      };
    };
  };

  mkSubscribeCommand =
    repository:
    lib.escapeShellArgs [
      (lib.getExe git-repo-subscribe)
      repository.url
      repository.path
      repository.partialCloneFilter
    ];

  repositories = lib.attrValues cfg.repositories;
  # 全リポジトリを並列に購読して、失敗したものは警告だけ出して続行します。
  subscribeAll = pkgs.writeShellApplication {
    name = "git-repo-subscribe-all";
    text = ''
      names=()
      pids=()
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: repository: ''
          ${mkSubscribeCommand repository} &
          names+=(${lib.escapeShellArg name})
          pids+=("$!")
        '') cfg.repositories
      )}
      for index in "''${!pids[@]}"; do
        if ! wait "''${pids[$index]}"; then
          echo "warning: unable to subscribe to Git repository ''${names[$index]}; continuing" >&2
        fi
      done
    '';
  };
  repositoryPaths = map (repository: repository.path) repositories;
  haveNestedRepositoryPaths = lib.any (
    path: lib.any (other: path != other && lib.hasPrefix "${path}/" other) repositoryPaths
  ) repositoryPaths;
in
{
  options.programs.git-repo-subscribe.repositories = lib.mkOption {
    type = lib.types.attrsOf repositoryType;
    default = { };
    description = "Git repositories cloned and safely updated in the background";
  };

  config = lib.mkIf (cfg.repositories != { }) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.length repositoryPaths == lib.length (lib.unique repositoryPaths);
            message = "programs.git-repo-subscribe.repositories must use unique worktree paths";
          }
          {
            assertion = !haveNestedRepositoryPaths;
            message = "programs.git-repo-subscribe.repositories must not use nested worktree paths";
          }
        ];
      }
      (lib.mkIf (!isTermux) {
        # activationの中で購読するとネットワークの応答を待つ間activationが終わりません。
        # NixOSではboot時のactivationが`systemd-user-sessions.service`より前に走るので、
        # ネットワークが繋がらない場所ではGitのタイムアウトまでディスプレイマネージャの起動が遅れます。
        # ユーザサービスに分離してactivationやGUIの起動と並行に動かします。
        # 切り替え時はsd-switchが`default.target`から引かれる停止中のユニットとして起動します。
        systemd.user.services.git-repo-subscribe = {
          Unit.Description = "Clone and update subscribed Git repositories";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe subscribeAll;
          };
          Install.WantedBy = [ "default.target" ];
        };
      })
      (lib.mkIf isTermux {
        # Termux環境ではsystemdが動作しないためactivationで直接実行します。
        home.activation.subscribeGitRepositories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${lib.getExe subscribeAll}
        '';
      })
    ]
  );
}
