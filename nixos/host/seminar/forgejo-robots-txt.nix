{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.containers.forgejo.config.services.forgejo) customDir;
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
  group =
    userAgents:
    lib.concatLines (
      map (ua: "User-agent: ${ua}") userAgents ++ map (path: "Disallow: ${path}") disallow
    );
  # Metaの`facebookexternalhit`は既定のrobots.txtを取得していますが、
  # `meta-externalagent`と`meta-webindexer`のUser-Agentでの取得は見えていません。
  # それでもこの2つは、断っている履歴のビューを大量に読みに来ます。
  # 同じ規則を、Metaを名指ししたグループでもう一度書きます。
  # 既定のものはグループの途中に空行があり、古い解釈ではそこでグループが終わるので、
  # 空行も入れません。
  robotsTxt = pkgs.writeText "robots.txt" ''
    ${group [ "*" ]}
    ${group [
      "meta-externalagent"
      "meta-webindexer"
    ]}'';
in
{
  # Forgejoは`custom/public/robots.txt`があると既定のrobots.txtの代わりに返します。
  containers.forgejo.config.systemd.tmpfiles.rules = [
    "d ${customDir}/public 0750 forgejo forgejo - -"
    "L+ ${customDir}/public/robots.txt - - - - ${robotsTxt}"
  ];
}
