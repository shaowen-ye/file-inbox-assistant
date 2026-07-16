#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/file-inbox-assistant-test.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "TEST FAILED: $1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_missing() {
  [ ! -e "$1" ] || fail "expected path to be absent: $1"
}

export FILE_INBOX_CONFIG="$ROOT/config.example.sh"
export FILE_INBOX_HOME="$ROOT"
export FILE_INBOX_STATE_DIR="$TEMP_ROOT/state"
export FILE_INBOX_INBOX="$TEMP_ROOT/inbox"
export FILE_INBOX_PENDING="$TEMP_ROOT/inbox/_Needs Review"
export FILE_INBOX_BACKLOG="$TEMP_ROOT/backlog"
export FILE_INBOX_ARCHIVE="$TEMP_ROOT/archive"
export FILE_INBOX_RULES="$ROOT/rules.example.md"
export FILE_INBOX_LEDGER="$TEMP_ROOT/state/ledger.jsonl"
export FILE_INBOX_STABLE_INTERVAL=0

mkdir -p "$FILE_INBOX_INBOX" "$FILE_INBOX_PENDING" "$FILE_INBOX_BACKLOG"
mkdir -p "$FILE_INBOX_ARCHIVE" "$FILE_INBOX_STATE_DIR" "$TEMP_ROOT/outside"

for file in "$ROOT/install.sh" "$ROOT/config.example.sh" "$ROOT"/scripts/*.sh "$ROOT"/swiftbar/*.sh; do
  bash -n "$file"
done

printf 'alpha\n' > "$FILE_INBOX_INBOX/draft.txt"
printf 'do not read\n' > "$FILE_INBOX_INBOX/.env.production"

scan_output="$("$ROOT/scripts/scan.sh")"
printf '%s' "$scan_output" | jq -e 'length == 2' >/dev/null
printf '%s' "$scan_output" | jq -e 'any(.[]; .name==".env.production" and .sensitive==true)' >/dev/null
printf '%s' "$scan_output" | jq -e 'any(.[]; .name=="draft.txt" and .sensitive==false)' >/dev/null

normalized_name='2026-01-01_example【draft】.txt'
"$ROOT/scripts/archive-move.sh" \
  --op move \
  --src "$FILE_INBOX_INBOX/draft.txt" \
  --dst-dir "$FILE_INBOX_ARCHIVE/Projects" \
  --new-name "$normalized_name" \
  --category Projects \
  --confidence 0.95 \
  --reason "synthetic test" \
  --batch batch-move >/dev/null

assert_file "$FILE_INBOX_ARCHIVE/Projects/$normalized_name"
assert_missing "$FILE_INBOX_INBOX/draft.txt"

printf 'alpha\n' > "$FILE_INBOX_INBOX/duplicate.txt"
"$ROOT/scripts/archive-move.sh" \
  --op move \
  --src "$FILE_INBOX_INBOX/duplicate.txt" \
  --dst-dir "$FILE_INBOX_ARCHIVE/Projects" \
  --new-name "$normalized_name" \
  --category Projects \
  --confidence 0.95 \
  --reason "duplicate test" \
  --batch batch-duplicate >/dev/null
assert_file "$FILE_INBOX_PENDING/_Duplicates/duplicate.txt"

printf 'different\n' > "$FILE_INBOX_INBOX/other.txt"
"$ROOT/scripts/archive-move.sh" \
  --op move \
  --src "$FILE_INBOX_INBOX/other.txt" \
  --dst-dir "$FILE_INBOX_ARCHIVE/Projects" \
  --new-name "$normalized_name" \
  --category Projects \
  --confidence 0.90 \
  --reason "name conflict test" \
  --batch batch-conflict >/dev/null
assert_file "$FILE_INBOX_ARCHIVE/Projects/2026-01-01_example_2【draft】.txt"

"$ROOT/scripts/archive-move.sh" \
  --op park \
  --src "$FILE_INBOX_INBOX/.env.production" \
  --confidence 0 \
  --reason "sensitive filename" \
  --batch batch-sensitive >/dev/null
assert_file "$FILE_INBOX_PENDING/.env.production"

printf 'escape\n' > "$FILE_INBOX_INBOX/escape.txt"
if "$ROOT/scripts/archive-move.sh" \
  --op move \
  --src "$FILE_INBOX_INBOX/escape.txt" \
  --dst-dir "$FILE_INBOX_ARCHIVE/../outside" \
  --new-name "escape.txt" \
  --batch batch-escape >/dev/null 2>&1; then
  fail "parent traversal was accepted"
fi
assert_file "$FILE_INBOX_INBOX/escape.txt"

ln -s "$TEMP_ROOT/outside" "$FILE_INBOX_ARCHIVE/link"
printf 'symlink\n' > "$FILE_INBOX_INBOX/symlink.txt"
if "$ROOT/scripts/archive-move.sh" \
  --op move \
  --src "$FILE_INBOX_INBOX/symlink.txt" \
  --dst-dir "$FILE_INBOX_ARCHIVE/link/subdir" \
  --new-name "symlink.txt" \
  --batch batch-symlink >/dev/null 2>&1; then
  fail "symlink traversal was accepted"
fi
assert_file "$FILE_INBOX_INBOX/symlink.txt"

"$ROOT/scripts/undo-last.sh" --batch batch-move >/dev/null
assert_file "$FILE_INBOX_ARCHIVE/Projects/$normalized_name"
"$ROOT/scripts/undo-last.sh" --batch batch-move --apply >/dev/null
assert_missing "$FILE_INBOX_ARCHIVE/Projects/$normalized_name"
assert_file "$FILE_INBOX_PENDING/draft.txt"

jq -e 'select(.op=="move" and .status=="done")' "$FILE_INBOX_LEDGER" >/dev/null
jq -e 'select(.op=="duplicate-skip" and .status=="duplicate")' "$FILE_INBOX_LEDGER" >/dev/null
jq -e 'select(.op=="undo" and .status=="undone")' "$FILE_INBOX_LEDGER" >/dev/null
"$ROOT/scripts/review-ledger.sh" --summary >/dev/null
"$ROOT/scripts/review-ledger.sh" --csv >/dev/null
assert_file "$FILE_INBOX_STATE_DIR/ledger.csv"

INSTALL_HOME="$TEMP_ROOT/install-home"
env \
  HOME="$INSTALL_HOME" \
  FILE_INBOX_HOME="$INSTALL_HOME/.local/share/file-inbox-assistant" \
  FILE_INBOX_STATE_DIR="$INSTALL_HOME/.local/state/file-inbox-assistant" \
  FILE_INBOX_INBOX="$INSTALL_HOME/Documents/File Inbox" \
  FILE_INBOX_PENDING="$INSTALL_HOME/Documents/File Inbox/_Needs Review" \
  FILE_INBOX_BACKLOG="$INSTALL_HOME/Documents/File Inbox Backlog" \
  FILE_INBOX_ARCHIVE="$INSTALL_HOME/Documents/File Archive" \
  XDG_CONFIG_HOME="$INSTALL_HOME/.config" \
  CLAUDE_HOME="$INSTALL_HOME/.claude" \
  SWIFTBAR_PLUGIN_DIR="$INSTALL_HOME/SwiftBar Plugins" \
  bash "$ROOT/install.sh" >/dev/null

assert_file "$INSTALL_HOME/.config/file-inbox-assistant/config.sh"
assert_file "$INSTALL_HOME/.claude/skills/file-inbox-assistant/SKILL.md"
assert_file "$INSTALL_HOME/SwiftBar Plugins/file-inbox-assistant.10s.sh"
if grep -R -E '__APP_HOME__|__CONFIG_FILE__' "$INSTALL_HOME/.claude" "$INSTALL_HOME/SwiftBar Plugins" >/dev/null 2>&1; then
  fail "installer left unresolved placeholders"
fi

echo "All smoke tests passed."
