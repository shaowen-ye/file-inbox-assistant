#!/bin/bash
# The only write primitive used by the classifier.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$DIR/lib.sh"

require_command "$JQ_BIN" jq

OP="" SRC="" DST_DIR="" NEW_NAME="" CATEGORY="" CONFIDENCE="0" REASON="" BATCH="" WRAP="off"
while [ $# -gt 0 ]; do
  case "$1" in
    --op) OP="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --dst-dir) DST_DIR="$2"; shift 2 ;;
    --new-name) NEW_NAME="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --confidence) CONFIDENCE="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    --batch) BATCH="$2"; shift 2 ;;
    --wrap) WRAP="$2"; shift 2 ;;
    *) echo "ERR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$BATCH" ] || BATCH="$(now_iso)"
case "$CONFIDENCE" in ''|*[!0-9.]*) CONFIDENCE="0" ;; esac

ledger_append() {
  local operation="$1" source="$2" destination="$3" status="$4" sha="${5:-}"
  local source_name destination_name
  source_name="$(/usr/bin/basename "$source")"
  destination_name="$(/usr/bin/basename "$destination")"
  mkdir -p "$STATE_DIR"
  "$JQ_BIN" -nc \
    --arg ts "$(now_iso)" --arg batch "$BATCH" --arg op "$operation" \
    --arg src "$source" --arg src_name "$source_name" \
    --arg dst "$destination" --arg dst_name "$destination_name" \
    --arg category "$CATEGORY" --argjson confidence "${CONFIDENCE:-0}" \
    --arg reason "$REASON" --arg sha "$sha" --arg status "$status" \
    '{ts:$ts,batch:$batch,op:$op,src:$src,src_name:$src_name,dst:$dst,dst_name:$dst_name,category:$category,confidence:$confidence,reason:$reason,sha256:$sha,status:$status}' \
    >> "$LEDGER"
}

fail() {
  local message="$1" attempted="${2:-}"
  echo "ERR: $message" >&2
  [ -n "$SRC" ] && ledger_append "$OP" "$SRC" "$attempted" error ""
  exit 1
}

mkdir -p "$STATE_DIR"
if [ "$OP" = "start" ]; then : > "$INFLIGHT"; echo "STARTED"; exit 0; fi
if [ "$OP" = "finish" ]; then rm -f "$INFLIGHT"; echo "FINISHED"; exit 0; fi

if [ -z "$SRC" ] || { [ ! -e "$SRC" ] && [ ! -L "$SRC" ]; }; then
  fail "source does not exist: $SRC"
fi
safe_inbox_source "$SRC" || fail "source is outside the configured inbox: $SRC"

acquire_move_lock || fail "another move operation is active"
trap release_move_lock EXIT INT TERM

split="$(split_ext_flag "$SRC")"
source_base="$(/usr/bin/basename "$SRC")"

if [ "$OP" = "park" ]; then
  mkdir -p "$PENDING"
  parked_name="$(find_free_name "$PENDING" "$source_base" "$split")"
  target="$PENDING/$parked_name"
  mv -n "$SRC" "$target" || fail "unable to park item" "$target"
  [ -e "$target" ] && [ ! -e "$SRC" ] || fail "park verification failed" "$target"
  ledger_append park "$SRC" "$target" pending ""
  echo "PARKED: $target"
  exit 0
fi

[ "$OP" = "move" ] || fail "--op must be move, park, start, or finish"
[ -n "$DST_DIR" ] && [ -n "$NEW_NAME" ] || fail "move requires --dst-dir and --new-name"
[ "$NEW_NAME" = "$(/usr/bin/basename "$NEW_NAME")" ] || fail "new name must be a single file name"
case "$NEW_NAME" in .|..) fail "unsafe new name" ;; esac
case "$WRAP" in on|off) ;; *) fail "--wrap must be on or off" ;; esac

DST_DIR="${DST_DIR%/}"
safe_destination_path "$DST_DIR" "$ARCH_ROOT" || fail "destination is outside the archive root or traverses a symlink: $DST_DIR"

if [ "$WRAP" = "on" ]; then
  case "$NEW_NAME" in
    *【*) container="${NEW_NAME%【*}" ;;
    *.*) container="${NEW_NAME%.*}" ;;
    *) container="$NEW_NAME" ;;
  esac
  container="${container#"${container%%[![:space:]]*}"}"
  container="${container%"${container##*[![:space:]]}"}"
  [ -n "$container" ] || fail "unable to derive container name"
  [ "$container" = "$(/usr/bin/basename "$container")" ] || fail "unsafe container name"
  case "$container" in .|..) fail "unsafe container name" ;; esac
  DST_DIR="$DST_DIR/$container"
  CATEGORY="${CATEGORY:+$CATEGORY/}$container"
  safe_destination_path "$DST_DIR" "$ARCH_ROOT" || fail "unsafe wrapped destination"
fi

mkdir -p "$DST_DIR" || fail "unable to create destination directory" "$DST_DIR/$NEW_NAME"
target="$DST_DIR/$NEW_NAME"

if [ -e "$target" ]; then
  if [ -f "$SRC" ] && [ -f "$target" ]; then
    source_sha="$(/usr/bin/shasum -a 256 "$SRC" 2>/dev/null | cut -d' ' -f1)"
    target_sha="$(/usr/bin/shasum -a 256 "$target" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "$source_sha" ] && [ "$source_sha" = "$target_sha" ]; then
      mkdir -p "$DUP_DIR"
      duplicate_name="$(find_free_name "$DUP_DIR" "$source_base" "$split")"
      duplicate_target="$DUP_DIR/$duplicate_name"
      mv -n "$SRC" "$duplicate_target" || fail "unable to park duplicate" "$duplicate_target"
      [ -e "$duplicate_target" ] && [ ! -e "$SRC" ] || fail "duplicate verification failed" "$duplicate_target"
      ledger_append duplicate-skip "$SRC" "$duplicate_target" duplicate "$source_sha"
      echo "DUPLICATE: $duplicate_target"
      exit 0
    fi
  fi
  NEW_NAME="$(find_free_name "$DST_DIR" "$NEW_NAME" "$split")"
  target="$DST_DIR/$NEW_NAME"
fi

mv -n "$SRC" "$target" || fail "move failed" "$target"
[ -e "$target" ] && [ ! -e "$SRC" ] || fail "move verification failed" "$target"

sha=""
[ -f "$target" ] && sha="$(/usr/bin/shasum -a 256 "$target" 2>/dev/null | cut -d' ' -f1)"
ledger_append move "$SRC" "$target" "done" "$sha"
echo "MOVED: $target"
