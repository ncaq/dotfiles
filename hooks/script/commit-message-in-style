#!/usr/bin/env raku
my IO::Path $commit-editmsg-path = IO::Path.new(@*ARGS[0]);
my IO::Path $project-root-path;
if !$commit-editmsg-path.is-absolute {
  $project-root-path = IO::Path.new((run 'git', 'rev-parse', '--show-toplevel', :out).out.slurp(:close).trim);
}
my Str $commit-msg = slurp($commit-editmsg-path.absolute($project-root-path));
my Str @prefixs = [
  'Merge ',
  'Revert ',
  'added: ',
  'changed: ',
  'cleaned: ',
  'deleted: ',
  'fixed: ',
  'modified: ',
  'renamed: ',
  'updated: ',
];

for @prefixs -> $prefix {
  if $commit-msg.starts-with($prefix) {
    exit 0
  }
}

die "commit-msg is invalid. commit-msg: $commit-msg";
