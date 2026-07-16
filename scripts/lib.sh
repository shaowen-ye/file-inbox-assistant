#!/bin/bash
# Shared helpers. Requires config.sh to be sourced first. Bash 3.2 compatible.

log() {
  printf '%s [file-inbox] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

require_command() {
  local value="$1" label="$2"
  if [ -z "$value" ] || [ ! -x "$value" ]; then
    echo "ERR: required command not found: $label" >&2
    exit 127
  fi
}

ext_lc() {
  local base
  base="$(/usr/bin/basename "$1")"
  case "$base" in
    *.*) printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]' ;;
    *) printf '' ;;
  esac
}

is_bundle() {
  local path="$1" ext item
  [ -d "$path" ] || return 1
  ext="$(ext_lc "$path")"
  [ -n "$ext" ] || return 1
  for item in "${BUNDLE_EXTS[@]}"; do
    [ "$ext" = "$item" ] && return 0
  done
  return 1
}

should_ignore() {
  local name pattern
  name="$(/usr/bin/basename "$1")"
  for pattern in "${IGNORE_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$name" in $pattern) return 0 ;; esac
  done
  return 1
}

is_sensitive() {
  local name lowered pattern
  name="$(/usr/bin/basename "$1")"
  lowered="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  for pattern in "${SENSITIVE_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$lowered" in $pattern) return 0 ;; esac
  done
  return 1
}

sample_sig() {
  local path="$1" kb count
  if [ -d "$path" ]; then
    kb="$(/usr/bin/du -sk "$path" 2>/dev/null | cut -f1)"
    count="$(/usr/bin/find "$path" -type f 2>/dev/null | wc -l | tr -d ' ')"
    printf '%s|%s' "${kb:-0}" "${count:-0}"
  else
    /usr/bin/stat -f '%z|%m' "$path" 2>/dev/null
  fi
}

age_seconds() {
  local path="$1" modified now
  modified="$(/usr/bin/stat -f '%m' "$path" 2>/dev/null)" || {
    printf '0'
    return
  }
  now="$(date +%s)"
  printf '%s' "$((now - modified))"
}

is_stable() {
  local path="$1" previous="" current="" hits=0 waited=0
  while [ "$waited" -lt "$STABLE_MAX_WAIT" ]; do
    current="$(sample_sig "$path")"
    if [ -n "$current" ] && [ "$current" = "$previous" ]; then
      hits=$((hits + 1))
      if [ "$hits" -ge "$STABLE_SAMPLES" ] &&
         [ "$(age_seconds "$path")" -ge "$STABLE_INTERVAL" ]; then
        return 0
      fi
    else
      hits=0
    fi
    previous="$current"
    sleep "$STABLE_INTERVAL"
    waited=$((waited + STABLE_INTERVAL))
  done
  return 1
}

# Newline characters in file names are intentionally unsupported because the
# Claude handoff and ledger are line-oriented.
list_actionable() {
  local path name
  [ -d "$INBOX" ] || return 0
  while IFS= read -r path; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    name="$(/usr/bin/basename "$path")"
    [ "$path" = "$PENDING" ] && continue
    should_ignore "$name" && continue
    printf '%s\n' "$path"
  done < <(/usr/bin/find "$INBOX" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
}

count_actionable() {
  list_actionable | grep -c . || true
}

notify() {
  local title="$1" message="$2" sound="${3:-Glass}"
  local escaped_title escaped_message
  escaped_title="${title//\"/\\\"}"
  escaped_message="${message//\"/\\\"}"
  "$OSA_BIN" -e "display notification \"$escaped_message\" with title \"$escaped_title\" sound name \"$sound\"" >/dev/null 2>&1 || true
}

find_free_name() {
  local directory="$1" name="$2" split_extension="$3"
  local base extension bracket core candidate number=2
  [ -e "$directory/$name" ] || { printf '%s' "$name"; return; }

  if [ "$split_extension" = "1" ]; then
    case "$name" in
      *.*) extension=".${name##*.}"; base="${name%.*}" ;;
      *) extension=""; base="$name" ;;
    esac
  else
    extension=""
    base="$name"
  fi

  case "$base" in
    *】) bracket="【${base##*【}"; core="${base%【*}" ;;
    *) bracket=""; core="$base" ;;
  esac

  while :; do
    candidate="${core}_${number}${bracket}${extension}"
    [ -e "$directory/$candidate" ] || { printf '%s' "$candidate"; return; }
    number=$((number + 1))
  done
}

split_ext_flag() {
  if [ -d "$1" ] && ! is_bundle "$1"; then printf '0'; else printf '1'; fi
}

contains_dot_component() {
  case "/$1/" in
    *'/../'*|*'/./'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Ensures a destination remains lexically under root and does not traverse an
# existing symlink. The configured root itself may be a user-selected symlink.
safe_destination_path() {
  local path="${1%/}" root="${2%/}" relative component current
  [ -n "$path" ] && [ -n "$root" ] || return 1
  contains_dot_component "$path" && return 1
  case "$path" in
    "$root"|"$root"/*) ;;
    *) return 1 ;;
  esac

  relative="${path#"$root"}"
  relative="${relative#/}"
  current="$root"
  while [ -n "$relative" ]; do
    component="${relative%%/*}"
    if [ "$component" = "$relative" ]; then
      relative=""
    else
      relative="${relative#"$component"/}"
    fi
    [ -n "$component" ] || return 1
    current="$current/$component"
    [ -L "$current" ] && return 1
  done
  return 0
}

safe_inbox_source() {
  local path="$1" root="${INBOX%/}"
  contains_dot_component "$path" && return 1
  case "$path" in "$root"/*) return 0 ;; *) return 1 ;; esac
}

acquire_move_lock() {
  local modified age now
  mkdir -p "$STATE_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then return 0; fi

  modified="$(/usr/bin/stat -f '%m' "$LOCK_DIR" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  age=$((now - modified))
  if [ "$age" -ge "$LOCK_TTL" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || return 1
    mkdir "$LOCK_DIR" 2>/dev/null
    return $?
  fi
  return 1
}

release_move_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
