#!/bin/bash
# Prints actionable top-level inbox entries as JSON.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$DIR/lib.sh"

require_command "$JQ_BIN" jq

objects=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  name="$(/usr/bin/basename "$path")"

  if is_bundle "$path"; then
    type="bundle"
    size=$(( $(/usr/bin/du -sk "$path" 2>/dev/null | cut -f1) * 1024 ))
  elif [ -d "$path" ]; then
    type="dir"
    size=$(( $(/usr/bin/du -sk "$path" 2>/dev/null | cut -f1) * 1024 ))
  else
    type="file"
    size="$(/usr/bin/stat -f '%z' "$path" 2>/dev/null || echo 0)"
  fi

  mtime="$(/usr/bin/stat -f '%m' "$path" 2>/dev/null || echo 0)"
  age="$(age_seconds "$path")"
  [ "$age" -ge "$STABLE_INTERVAL" ] && stable=true || stable=false
  is_sensitive "$name" && sensitive=true || sensitive=false

  object="$("$JQ_BIN" -nc \
    --arg path "$path" --arg name "$name" --arg type "$type" \
    --argjson size "${size:-0}" --argjson mtime "${mtime:-0}" \
    --argjson age "${age:-0}" --argjson stable "$stable" \
    --argjson sensitive "$sensitive" \
    '{path:$path,name:$name,type:$type,size:$size,mtime:$mtime,age:$age,stable:$stable,sensitive:$sensitive}')"
  objects="$objects$object
"
done < <(list_actionable)

if [ -z "$objects" ]; then
  printf '[]\n'
else
  printf '%s' "$objects" | "$JQ_BIN" -s '.'
fi
