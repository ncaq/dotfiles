{ importDirModules, ... }:
{
  imports = importDirModules ./. ++ [ ./github-runner ];
}
