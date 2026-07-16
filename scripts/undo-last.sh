#!/bin/bash
# Dry-run-first rollback for the most recent batch or selected records.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$DIR/lib.sh"

require_command "$JQ_BIN" jq

MODE=dry BATCH="" LAST_N=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) MODE=apply; shift ;;
    --dry-run) MODE=dry; shift ;;
    --batch) BATCH="$2"; shift 2 ;;
    --last) LAST_N="$2"; shift 2 ;;
    *) echo "ERR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -f "$LEDGER" ] || { echo "No ledger found: $LEDGER"; exit 0; }

if [ -z "$BATCH" ] && [ -z "$LAST_N" ]; then
  BATCH="$("$JQ_BIN" -rs 'map(select(.op=="move" and .status=="done")) | sort_by(.ts) | last | .batch // empty' "$LEDGER")"
  [ -n "$BATCH" ] || { echo "No completed move is available to undo."; exit 0; }
fi

records="$(mktemp)"
trap 'rm -f "$records"; release_move_lock' EXIT INT TERM
if [ -n "$LAST_N" ]; then
  "$JQ_BIN" -c 'select(.op=="move" and .status=="done")' "$LEDGER" | tail -n "$LAST_N" > "$records"
else
  "$JQ_BIN" -c --arg batch "$BATCH" 'select(.op=="move" and .status=="done" and .batch==$batch)' "$LEDGER" > "$records"
fi

count="$(grep -c . "$records" 2>/dev/null || true)"
echo "Undo candidates: $count (mode=$MODE, batch=${BATCH:-last-$LAST_N})"

if [ "$MODE" = apply ]; then
  acquire_move_lock || { echo "ERR: another move operation is active" >&2; exit 1; }
  mkdir -p "$PENDING" "$STATE_DIR"
  : > "$INFLIGHT"
fi

index=0
lines=()
while IFS= read -r line; do lines[index]="$line"; index=$((index + 1)); done < "$records"

index=$((index - 1))
while [ "$index" -ge 0 ]; do
  line="${lines[$index]}"
  index=$((index - 1))
  [ -n "$line" ] || continue

  destination="$(printf '%s' "$line" | "$JQ_BIN" -r '.dst')"
  source="$(printf '%s' "$line" | "$JQ_BIN" -r '.src')"
  source_name="$(/usr/bin/basename "$source")"
  safe_destination_path "$destination" "$ARCH_ROOT" || {
    echo "SKIP unsafe archived path: $destination"
    continue
  }

  already_undone="$("$JQ_BIN" -rs --arg path "$destination" 'any(.[]; .op=="undo" and .src==$path)' "$LEDGER")"
  [ "$already_undone" = true ] && { echo "SKIP already undone: $destination"; continue; }
  [ -e "$destination" ] || { echo "SKIP missing: $destination"; continue; }

  restore="$PENDING/$(find_free_name "$PENDING" "$source_name" "$(split_ext_flag "$destination")")"
  echo "$destination -> $restore"

  if [ "$MODE" = apply ]; then
    mv -n "$destination" "$restore" || { echo "ERR: restore failed: $destination" >&2; continue; }
    [ -e "$restore" ] && [ ! -e "$destination" ] || { echo "ERR: restore verification failed" >&2; continue; }
    "$JQ_BIN" -nc --arg ts "$(now_iso)" --arg batch "${BATCH:-mixed}" \
      --arg src "$destination" --arg dst "$restore" \
      '{ts:$ts,batch:$batch,op:"undo",src:$src,src_name:($src|split("/")|last),dst:$dst,dst_name:($dst|split("/")|last),category:"",confidence:0,reason:"undo-last",sha256:"",status:"undone"}' \
      >> "$LEDGER"
  fi
done

if [ "$MODE" = dry ]; then
  echo "Dry run only. Re-run with --apply to move these items."
else
  rm -f "$INFLIGHT"
fi
