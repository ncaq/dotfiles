{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.containers.forgejo.config.services) forgejo;
  # Forgejo 15の既定のrobots.txtが`User-agent: *`に断っているパス。
  # 手で写したものなので、Forgejoの更新で既定のものが変わっても追従せず、漏れが出ます。
  # クロールを断るのはセキュリティのためではなく、漏れても大した問題にならないので、
  # 追従する仕組みは考えません。
  disallow = [
    "/api/"
    "/avatars/"
    "/user/"
    "/swagger.*.json"
    "/explore/*?*"
    "/repo/create"
    "/repo/migrate"
    "/org/create"
    "/*/*/fork"
    "/*/*/watchers"
    "/*/*/stargazers"
    "/*/*/forks"
    "/*/*/src/"
    "/*/*/blame/"
    "/*/*/commit/"
    "/*/*/commits/"
    "/*/*/raw/"
    "/*/*/media/"
    "/*/*/tags"
    "/*/*/graph"
    "/*/*/branches"
    "/*/*/compare"
    "/*/*/lastcommit/"
    "/*/*/rss/branch/"
    "/*/*/atom/branch/"
    "/*/*/activity"
    "/*/*/activity_author_data"
    "/*/*/actions"
    "/*/*/projects"
    "/*/*/labels"
    "/*/*/milestones"
    "/*/*/find/"
    "/*/*/tree-list/"
    "/*/*/search/"
    "/*/-/code"
    "/*/*/issues/new"
    "/*/*/pulls/*/files"
    "/*/*/pulls/*/commits"
    "/attachments/"
    "/*/*/attachments/"
    "/*/*/issues/*/attachments/"
    "/*/*/pulls/*/attachments/"
    "/*/*/releases/attachments"
    "/*/*/releases/download"
    "/*/*/archive/"
    "/*.bundle$"
    "/*.patch$"
    "/*.diff$"
    "/*.atom$"
    "/*.rss$"
    "/*lang=*"
    "/*redirect_to=*"
    "/*tab=*"
    "/*q=*"
    "/*sort=*"
    "/*repo-search-archived=*"
  ];
  # Metaの`meta-externalagent`と`meta-webindexer`は、
  # 既定のrobots.txtが断っている履歴のビューを大量に読みに来ていました。
  # 既定のものはグループの途中に空行があり、古い解釈ではそこでグループが終わるので、
  # 同じ規則を空行を入れずに書きます。
  # 空行を除くことと、Metaを名指ししたグループを足すことを同時に行ったところ、
  # Metaは履歴のビューを読みに来なくなりました。
  # どちらが効いたのかを切り分けるために、今は名指しのグループを外して様子を見ています。
  # ref https://codeberg.org/forgejo/forgejo/issues/15333
  robotsTxt = pkgs.writeText "robots.txt" (
    lib.concatLines ([ "User-agent: *" ] ++ map (path: "Disallow: ${path}") disallow)
  );
in
{
  # Forgejoは`custom/public/robots.txt`があると既定のrobots.txtの代わりに返します。
  containers.forgejo.config.systemd.tmpfiles.rules = [
    "d ${forgejo.customDir}/public 0750 ${forgejo.user} ${forgejo.group} - -"
    "L+ ${forgejo.customDir}/public/robots.txt - - - - ${robotsTxt}"
  ];
}
