#!/bin/bash
# Starts or attaches to the watcher + Claude tmux session.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$DIR/lib.sh"

require_command "$TMUX_BIN" tmux
require_command "$CLAUDE_BIN" claude
require_command "$JQ_BIN" jq
[ -f "$RULES_FILE" ] || { echo "ERR: missing rules: $RULES_FILE" >&2; exit 2; }

mkdir -p "$INBOX" "$PENDING" "$ARCH_ROOT" "$STATE_DIR"

attach_or_switch() {
  if [ -n "${TMUX:-}" ]; then
    exec "$TMUX_BIN" switch-client -t "$SESSION"
  else
    exec "$TMUX_BIN" attach -t "$SESSION"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  echo "Attaching to existing '$SESSION' session..."
  attach_or_switch
fi

tools=(
  "Bash($DIR/archive-move.sh:*)"
  "Bash($DIR/scan.sh:*)"
  "Bash($DIR/undo-last.sh:*)"
  "Bash(du:*)"
  "Bash(shasum:*)"
  "Bash(stat:*)"
  "Bash(file:*)"
  "Bash(mdls:*)"
  "Bash(find:*)"
  "Read"
)
[ -n "$PDFTOTEXT_BIN" ] && tools[${#tools[@]}]="Bash(pdftotext:*)"
[ -n "$PDFINFO_BIN" ] && tools[${#tools[@]}]="Bash(pdfinfo:*)"
[ -n "$PANDOC_BIN" ] && tools[${#tools[@]}]="Bash(pandoc:*)"

claude_command="$(shell_quote "$CLAUDE_BIN") --model $(shell_quote "$MODEL")"
claude_command="$claude_command --permission-mode acceptEdits"
claude_command="$claude_command --add-dir $(shell_quote "$INBOX")"
claude_command="$claude_command --allowedTools"
for tool in "${tools[@]}"; do
  claude_command="$claude_command $(shell_quote "$tool")"
done

echo "Starting '$SESSION' with watcher and Claude windows..."

watcher_command="exec bash $(shell_quote "$DIR/watcher-loop.sh")"
watcher_id="$("$TMUX_BIN" new-session -d -P -F '#{window_id}' \
  -s "$SESSION" -n "$WATCHER_WINDOW" -c "$ARCH_ROOT" "$watcher_command")"
"$TMUX_BIN" set-option -w -t "$watcher_id" automatic-rename off
"$TMUX_BIN" set-option -w -t "$watcher_id" allow-rename off

has_backlog=0
if [ "$(count_actionable)" -gt 0 ]; then
  has_backlog=1
  : > "$INFLIGHT"
fi

claude_id="$("$TMUX_BIN" new-window -t "$SESSION" -P -F '#{window_id}' \
  -n "$CLAUDE_WINDOW" -c "$ARCH_ROOT" "$claude_command")"
"$TMUX_BIN" set-option -w -t "$claude_id" automatic-rename off
"$TMUX_BIN" set-option -w -t "$claude_id" allow-rename off
"$TMUX_BIN" rename-window -t "$claude_id" "$CLAUDE_WINDOW"
"$TMUX_BIN" rename-window -t "$watcher_id" "$WATCHER_WINDOW"

ready=0
attempt=0
while [ "$attempt" -lt 40 ]; do
  process="$("$TMUX_BIN" display-message -p -t "$INJECT_TARGET" '#{pane_current_command}' 2>/dev/null || echo '')"
  case "$process" in
    ''|zsh|-zsh|bash|-bash|sh|-sh|login) sleep 1 ;;
    *) ready=1; break ;;
  esac
  attempt=$((attempt + 1))
done
[ "$ready" -eq 1 ] || echo "Warning: Claude readiness was not confirmed."
sleep 2

if [ "$has_backlog" -eq 1 ]; then
  item_count="$(count_actionable)"
  "$TMUX_BIN" send-keys -t "$INJECT_TARGET" C-u
  "$TMUX_BIN" send-keys -t "$INJECT_TARGET" -l "$INJECT_CMD"
  sleep 0.5
  "$TMUX_BIN" send-keys -t "$INJECT_TARGET" Enter
  echo "Triggered sorting for $item_count existing item(s)."
else
  rm -f "$INFLIGHT"
fi

"$TMUX_BIN" select-window -t "$INJECT_TARGET"
attach_or_switch
