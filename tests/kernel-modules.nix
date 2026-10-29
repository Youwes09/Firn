# A reduced configuration drops modules silently when a dependency goes.
{ pkgs, kernel }:
pkgs.runCommand "firn-kernel-modules" { } ''
  dir=${kernel.modules}/lib/modules/${kernel.modDirVersion}
  { find "$dir" -name '*.ko*'; cat "$dir/modules.builtin"; } \
    | sed -E 's|.*/||; s|\.ko.*||; s|-|_|g' | sort -u > available
  missing=0
  while read -r name; do
    case "$name" in "" | "#"*) continue ;; esac
    if ! grep -qx "''${name//-/_}" available; then
      echo "missing: $name"
      missing=1
    fi
  done < ${../pkgs/linux/required-modules.txt}
  [ "$missing" = 0 ] || exit 1
  echo ok > $out
''
