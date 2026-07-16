#!/bin/bash
# <bitbar.title>File Inbox Assistant</bitbar.title>
# <bitbar.version>0.1.0</bitbar.version>
# <bitbar.desc>Safe, auditable file inbox controls for Claude Code.</bitbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.alwaysVisible>true</swiftbar.alwaysVisible>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.npm-global/bin"
export LANG="${LANG:-en_US.UTF-8}"

APP_HOME="__APP_HOME__"
CONFIG_FILE="__CONFIG_FILE__"
SELF="$0"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$APP_HOME/scripts/lib.sh" ]; then
  echo "📥⚠️"
  echo "---"
  echo "File Inbox Assistant is not fully installed | color=red"
  echo "Run install.sh from the project repository"
  exit 0
fi

# shellcheck disable=SC1090
. "$CONFIG_FILE"
# shellcheck disable=SC1091
. "$APP_HOME/scripts/lib.sh"

shell_quote() {
  printf '%q' "$1"
}

run_in_terminal() {
  local command_text="$1"
  if [ "$TERMINAL_APP" = "iTerm" ]; then
    "$OSA_BIN" - "$command_text" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set commandText to item 1 of argv
  tell application "iTerm"
    create window with default profile command commandText
    activate
  end tell
end run
APPLESCRIPT
  else
    "$OSA_BIN" - "$command_text" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set commandText to item 1 of argv
  tell application "Terminal"
    do script commandText
    activate
  end tell
end run
APPLESCRIPT
  fi
}

move_backlog() {
  local limit="$1" moved=0 path
  mkdir -p "$INBOX"
  while IFS= read -r path; do
    [ "$moved" -ge "$limit" ] && break
    [ -e "$path" ] || continue
    mv -n "$path" "$INBOX/" 2>/dev/null && moved=$((moved + 1))
  done < <(/usr/bin/find "$BACKLOG" -mindepth 1 -maxdepth 1 -print 2>/dev/null | sort)
  notify "File Inbox Assistant" "Moved $moved backlog item(s) into the inbox"
}

case "${1:-}" in
  start)
    run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/start-session.sh")"
    exit 0
    ;;
  sort)
    if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" C-u
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" -l "$INJECT_CMD"
      "$TMUX_BIN" send-keys -t "$INJECT_TARGET" Enter
      notify "File Inbox Assistant" "Sorting triggered"
    else
      run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/start-session.sh")"
    fi
    exit 0
    ;;
  backlog5) move_backlog 5; exit 0 ;;
  backlogall) move_backlog 100000; exit 0 ;;
  undo) run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/undo-last.sh")"; exit 0 ;;
  review) run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/review-ledger.sh") --recent 30"; exit 0 ;;
  pending) run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/review-ledger.sh") --pending"; exit 0 ;;
  summary) run_in_terminal "bash $(shell_quote "$APP_HOME/scripts/review-ledger.sh") --summary"; exit 0 ;;
  csv) "$APP_HOME/scripts/review-ledger.sh" --csv >/dev/null 2>&1; exit 0 ;;
  open-inbox) open "$INBOX"; exit 0 ;;
  open-backlog) open "$BACKLOG"; exit 0 ;;
  open-pending) open "$PENDING"; exit 0 ;;
  open-archive) open "$ARCH_ROOT"; exit 0 ;;
  open-config) open -e "$CONFIG_FILE"; exit 0 ;;
  open-rules) open -e "$RULES_FILE"; exit 0 ;;
  privacy) open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"; exit 0 ;;
esac

if ! ls "$INBOX" >/dev/null 2>&1; then
  echo "📥⚠️"
  echo "---"
  echo "SwiftBar cannot read the configured inbox | color=red"
  echo "Open Full Disk Access settings | bash=\"$SELF\" param1=privacy terminal=false"
  echo "Allow the official SwiftBar app, then refresh"
  exit 0
fi

inbox_count="$(count_actionable)"
backlog_count="$(/usr/bin/find "$BACKLOG" -mindepth 1 -maxdepth 1 -print 2>/dev/null | grep -c . || true)"
pending_count="$(/usr/bin/find "$PENDING" -mindepth 1 -maxdepth 1 -print 2>/dev/null | grep -c . || true)"
if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  run_status="● Running"
  run_color=green
else
  run_status="○ Stopped"
  run_color=orange
fi

[ "$inbox_count" -gt 0 ] && echo "📥 $inbox_count" || echo "📥"
echo "---"
echo "File Inbox Assistant | size=11 color=gray"
echo "Status: $run_status | color=$run_color"
echo "Inbox $inbox_count · Backlog $backlog_count · Review $pending_count | size=12"
echo "Model: $MODEL | size=11 color=gray"
echo "---"
echo "▶︎ Start / enter session | bash=\"$SELF\" param1=start terminal=false"
echo "📥 Sort inbox now | bash=\"$SELF\" param1=sort terminal=false refresh=true"
echo "---"
echo "Backlog"
echo "-- Move 5 items to inbox | bash=\"$SELF\" param1=backlog5 terminal=false refresh=true"
echo "-- Move all items to inbox | bash=\"$SELF\" param1=backlogall terminal=false refresh=true"
echo "-- Open backlog | bash=\"$SELF\" param1=open-backlog terminal=false"
echo "↩︎ Preview last undo | bash=\"$SELF\" param1=undo terminal=false"
echo "---"
echo "Ledger"
echo "-- Recent 30 | bash=\"$SELF\" param1=review terminal=false"
echo "-- Needs review | bash=\"$SELF\" param1=pending terminal=false"
echo "-- Batch summary | bash=\"$SELF\" param1=summary terminal=false"
echo "-- Export CSV | bash=\"$SELF\" param1=csv terminal=false"
echo "---"
echo "Folders"
echo "-- Open inbox | bash=\"$SELF\" param1=open-inbox terminal=false"
echo "-- Open needs review | bash=\"$SELF\" param1=open-pending terminal=false"
echo "-- Open archive | bash=\"$SELF\" param1=open-archive terminal=false"
echo "---"
echo "Settings"
echo "-- Edit rules | bash=\"$SELF\" param1=open-rules terminal=false"
echo "-- Edit config | bash=\"$SELF\" param1=open-config terminal=false"
echo "Refresh | refresh=true"
