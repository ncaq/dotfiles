{
  username,
  osConfig ? null,
  ...
}:
let
  # konokaプラグインは`${XDG_RUNTIME_DIR:-/tmp}/coding-agent-work/`を使用します。
  # NixOS環境では`osConfig`からUIDを取得し、非NixOS環境では`/tmp`へフォールバックします。
  codingAgentWorkDirFullPath =
    let
      uid = if osConfig != null then osConfig.users.users.${username}.uid else null;
      base = if uid != null then "/run/user/${toString uid}" else "/tmp";
    in
    "${base}/coding-agent-work/";
in
{
  _module.args = { inherit codingAgentWorkDirFullPath; };
}
