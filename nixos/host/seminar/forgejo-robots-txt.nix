{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.containers.forgejo.config.services) forgejo;
  # Forgejo 15の既定のrobots.txtが`User-agent: *`に断っているパス。
  # 既定のものが空行で区切っているまとまりごとに分けています。
  # 手で写したものなので、Forgejoの更新で既定のものが変わっても追従せず、漏れが出ます。
  # クロールを断るのはセキュリティのためではなく、漏れても大した問題にならないので、
  # 追従する仕組みは考えません。
  disallowBlocks = [
    [
      "/api/"
      "/avatars/"
      "/user/"
      "/swagger.*.json"
      "/explore/*?*"
    ]
    [
      "/repo/create"
      "/repo/migrate"
      "/org/create"
      "/*/*/fork"
    ]
    [
      "/*/*/watchers"
      "/*/*/stargazers"
      "/*/*/forks"
    ]
    [
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
    ]
    [
      "/*/*/activity"
      "/*/*/activity_author_data"
    ]
    [
      "/*/*/actions"
      "/*/*/projects"
      "/*/*/labels"
      "/*/*/milestones"
    ]
    [
      "/*/*/find/"
      "/*/*/tree-list/"
      "/*/*/search/"
      "/*/-/code"
    ]
    [
      "/*/*/issues/new"
      "/*/*/pulls/*/files"
      "/*/*/pulls/*/commits"
    ]
    [
      "/attachments/"
      "/*/*/attachments/"
      "/*/*/issues/*/attachments/"
      "/*/*/pulls/*/attachments/"
      "/*/*/releases/attachments"
      "/*/*/releases/download"
    ]
    [
      "/*/*/archive/"
      "/*.bundle$"
      "/*.patch$"
      "/*.diff$"
      "/*.atom$"
      "/*.rss$"
    ]
    [
      "/*lang=*"
      "/*redirect_to=*"
      "/*tab=*"
      "/*q=*"
      "/*sort=*"
      "/*repo-search-archived=*"
    ]
  ];
  disallowLines = map (path: "Disallow: ${path}");
  # Forgejo 15の既定のrobots.txtと1バイトも違わない内容。
  # 冒頭のコメントも、グループの途中の空行も、そのまま再現します。
  defaultLines = [
    "# The default Forgejo robots.txt"
    "# For more information: https://forgejo.org/docs/latest/admin/search-engines-indexation/"
    ""
    "User-agent: *"
  ]
  ++ lib.concatLists (lib.intersperse [ "" ] (map disallowLines disallowBlocks));
  # Metaの`meta-externalagent`と`meta-webindexer`は、
  # 既定のrobots.txtが断っている履歴のビューを大量に読みに来ていました。
  # 同じ規則をこの2つを名指ししたグループで書くと止まり、
  # 名指しを外して`User-agent: *`だけに戻すと再開しました。
  # `User-agent: *`のグループから空行を除いても除かなくても、Metaには効きませんでした。
  # 今は、既定のものには一切手を入れず、名指しのグループを後ろへ足すだけで止まるのかを確かめています。
  # 止まれば、Forgejoの既定のrobots.txtへ足す最小の変更が分かります。
  # 名指しのグループの中には空行を入れていません。
  # 止まることを確かめた時の書き方のままにして、変える条件を既定の部分だけにするためです。
  # ref https://codeberg.org/forgejo/forgejo/issues/15333
  metaLines = [
    "User-agent: meta-externalagent"
    "User-agent: meta-webindexer"
  ]
  ++ disallowLines (lib.concatLists disallowBlocks);
  robotsTxt = pkgs.writeText "robots.txt" (lib.concatLines (defaultLines ++ [ "" ] ++ metaLines));
in
{
  # Forgejoは`custom/public/robots.txt`があると既定のrobots.txtの代わりに返します。
  containers.forgejo.config.systemd.tmpfiles.rules = [
    "d ${forgejo.customDir}/public 0750 ${forgejo.user} ${forgejo.group} - -"
    "L+ ${forgejo.customDir}/public/robots.txt - - - - ${robotsTxt}"
  ];
}
