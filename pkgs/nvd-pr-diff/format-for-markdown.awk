# nvd diffの標準出力をMarkdownリストに整形するawkスクリプト。
# Version changesセクションのnixos-system-*行は除外します。
# nixos-system-*行はdotfiles更新で必ず変わるのでノイズになるためです。

BEGIN { section = ""; has_content = 0; closure = "" }

/^Version changes:/  { section = "change"; next }
/^Removed packages:/ { section = "removed"; next }
/^Added packages:/   { section = "added";   next }

/^Closure size:/ {
  section = ""
  closure = $0
  sub(/^Closure size:[[:space:]]*/, "", closure)
  next
}

/^[[:space:]]*$/ { next }
/^<<<|^>>>/ { next }

{
  if (section == "change") {
    if ($3 ~ /^nixos-system-/) next
    type = substr($1, 2, 1)
    pkg = $3
    from = $4
    # $5 is "->"
    to = ""
    for (i = 6; i <= NF; i++) to = to (i == 6 ? "" : " ") $i
    print "- [" type "] " pkg ": " from " -> " to
    has_content = 1
  } else if (section == "added" || section == "removed") {
    if ($3 ~ /^nixos-system-/) next
    type = substr($1, 2, 1)
    pkg = $3
    ver = ""
    for (i = 4; i <= NF; i++) ver = ver (i == 4 ? "" : " ") $i
    print "- [" type "] " pkg ": " ver
    has_content = 1
  }
}

END {
  if (has_content == 0) print "no version changes"
  if (closure != "") {
    print ""
    print "Closure size: " closure
  }
}
