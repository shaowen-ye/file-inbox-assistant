#!/bin/bash
# Polls the inbox from inside the terminal-owned tmux session.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$DIR/lib.sh"

require_command "$TMUX_BIN" tmux

signature() {
  list_actionable | while IFS= read -r path; do
    printf '%s:%s\n' "$(/usr/bin/basename "$path")" "$(sample_sig "$path")"
  done | sort | /usr/bin/shasum -a 256 | cut -d' ' -f1
}

mkdir -p "$STATE_DIR"
log "watcher started (poll=${POLL_INTERVAL}s, target=$INJECT_TARGET)"
last_signature=""

while true; do
  sleep "$POLL_INTERVAL"

  if ! "$TMUX_BIN" list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$CLAUDE_WINDOW"; then
    log "Claude window is gone; watcher stopped"
    exit 0
  fi

  if [ -f "$INFLIGHT" ]; then
    modified="$(/usr/bin/stat -f '%m' "$INFLIGHT" 2>/dev/null || echo 0)"
    age=$(( $(date +%s) - modified ))
    [ "$age" -lt "$INFLIGHT_TTL" ] && continue
    rm -f "$INFLIGHT"
  fi

  if [ "$(count_actionable)" -eq 0 ]; then
    last_signature=""
    continue
  fi

  current_signature="$(signature)"
  [ "$current_signature" = "$last_signature" ] && continue

  while IFS= read -r path; do
    [ -e "$path" ] || continue
    is_stable "$path" || log "item did not stabilize before timeout: $path"
  done < <(list_actionable)

  [ "$(count_actionable)" -eq 0 ] && { last_signature=""; continue; }
  item_count="$(count_actionable)"
  current_signature="$(signature)"

  pane_command="$("$TMUX_BIN" display-message -p -t "$INJECT_TARGET" '#{pane_current_command}' 2>/dev/null || echo '')"
  case "$pane_command" in
    ''|zsh|-zsh|bash|-bash|sh|-sh|login)
      notify "File Inbox Assistant" "Claude is not running; $item_count item(s) are waiting"
      log "Claude process not detected; injection skipped"
      ;;
    *)
      : > "$INFLIGHT"
      last_signature="$current_signature"
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" C-u
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" -l "$INJECT_CMD"
      sleep 0.5
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" Enter
      notify "File Inbox Assistant" "Sorting triggered for $item_count item(s)"
      log "injected $INJECT_CMD for $item_count item(s)"
      ;;
  esac
done
