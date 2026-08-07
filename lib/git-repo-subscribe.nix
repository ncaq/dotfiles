{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.programs.git-repo-subscribe;
  git-repo-subscribe = pkgs.callPackage ../pkgs/git-repo-subscribe { };

  gitRemoteType = lib.types.addCheck lib.types.str (
    url: builtins.match "^(https|ssh|file)://[^[:space:]]+$" url != null
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
        default = "blob:limit=1m";
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
  repositoryPaths = map (repository: repository.path) repositories;
  haveNestedRepositoryPaths = lib.any (
    path: lib.any (other: path != other && lib.hasPrefix "${path}/" other) repositoryPaths
  ) repositoryPaths;
in
{
  options.programs.git-repo-subscribe.repositories = lib.mkOption {
    type = lib.types.attrsOf repositoryType;
    default = { };
    description = "Git repositories cloned and safely updated during activation";
  };

  config = lib.mkIf (cfg.repositories != { }) {
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

    home.activation.subscribeGitRepositories = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStringsSep "\n" (
        repository: "$DRY_RUN_CMD ${mkSubscribeCommand repository}"
      ) repositories
    );
  };
}
