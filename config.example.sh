#!/bin/bash
# Copy to ~/.config/file-inbox-assistant/config.sh and customize.
# Bash 3.2 compatible.
# shellcheck disable=SC2034

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.npm-global/bin"
export LANG="${LANG:-en_US.UTF-8}"

find_command() {
  command -v "$1" 2>/dev/null || true
}

APP_HOME="${FILE_INBOX_HOME:-$HOME/.local/share/file-inbox-assistant}"
STATE_DIR="${FILE_INBOX_STATE_DIR:-$HOME/.local/state/file-inbox-assistant}"
INBOX="${FILE_INBOX_INBOX:-$HOME/Documents/File Inbox}"
PENDING="${FILE_INBOX_PENDING:-$INBOX/_Needs Review}"
BACKLOG="${FILE_INBOX_BACKLOG:-$HOME/Documents/File Inbox Backlog}"
ARCH_ROOT="${FILE_INBOX_ARCHIVE:-$HOME/Documents/File Archive}"
RULES_FILE="${FILE_INBOX_RULES:-$HOME/.config/file-inbox-assistant/rules.md}"
LEDGER="${FILE_INBOX_LEDGER:-$STATE_DIR/ledger.jsonl}"
DUP_DIR="$PENDING/_Duplicates"

SESSION="${FILE_INBOX_SESSION:-file-inbox}"
WATCHER_WINDOW="watcher"
CLAUDE_WINDOW="claude"
INJECT_TARGET="$SESSION:$CLAUDE_WINDOW"
INJECT_CMD="/sort-file-inbox"

POLL_INTERVAL="${FILE_INBOX_POLL_INTERVAL:-5}"
STABLE_SAMPLES="${FILE_INBOX_STABLE_SAMPLES:-2}"
STABLE_INTERVAL="${FILE_INBOX_STABLE_INTERVAL:-3}"
STABLE_MAX_WAIT="${FILE_INBOX_STABLE_MAX_WAIT:-120}"
INFLIGHT_TTL="${FILE_INBOX_INFLIGHT_TTL:-1800}"
LOCK_TTL="${FILE_INBOX_LOCK_TTL:-600}"
CONFIDENCE_THRESHOLD="${FILE_INBOX_CONFIDENCE_THRESHOLD:-0.80}"

MODEL="${FILE_INBOX_MODEL:-sonnet}"
TERMINAL_APP="${FILE_INBOX_TERMINAL:-Terminal}" # Terminal or iTerm

TMUX_BIN="${TMUX_BIN:-$(find_command tmux)}"
CLAUDE_BIN="${CLAUDE_BIN:-$(find_command claude)}"
JQ_BIN="${JQ_BIN:-$(find_command jq)}"
PDFTOTEXT_BIN="${PDFTOTEXT_BIN:-$(find_command pdftotext)}"
PDFINFO_BIN="${PDFINFO_BIN:-$(find_command pdfinfo)}"
PANDOC_BIN="${PANDOC_BIN:-$(find_command pandoc)}"
OSA_BIN="${OSA_BIN:-/usr/bin/osascript}"

INFLIGHT="$STATE_DIR/inflight"
LOCK_DIR="$STATE_DIR/move.lock"
WATCH_LOG="$STATE_DIR/watcher.log"

IGNORE_GLOBS=(
  ".DS_Store" ".localized" ".Spotlight-V100" ".fseventsd"
  ".TemporaryItems" ".apdisk" "Icon?" "*.crdownload" "*.part"
  "*.partial" "*.download" '~$*' "*.tmp" "*.sb-*"
)

# These entries remain visible to the classifier as sensitive=true, but their
# contents must not be opened. The default skill parks them for manual review.
SENSITIVE_GLOBS=(
  ".env" ".env.*" "*.pem" "*.key" "*.p12" "*.pfx" "id_rsa*"
  "*password*" "*passwd*" "*secret*" "*token*" "*credential*"
)

BUNDLE_EXTS=(
  app rtfd key pages numbers photoslibrary fcpbundle band sparsebundle
  framework bundle
)
