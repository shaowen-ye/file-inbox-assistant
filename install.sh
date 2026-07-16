#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_HOME="${FILE_INBOX_HOME:-$HOME/.local/share/file-inbox-assistant}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/file-inbox-assistant"
STATE_DIR="${FILE_INBOX_STATE_DIR:-$HOME/.local/state/file-inbox-assistant}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/Library/Application Support/SwiftBar/Plugins}"
CONFIG_FILE="$CONFIG_DIR/config.sh"
RULES_FILE="$CONFIG_DIR/rules.md"

mkdir -p "$APP_HOME/scripts" "$CONFIG_DIR" "$STATE_DIR"
mkdir -p "$CLAUDE_HOME/skills/file-inbox-assistant" "$CLAUDE_HOME/commands"
mkdir -p "$PLUGIN_DIR"

for file in "$ROOT"/scripts/*.sh; do
  install -m 755 "$file" "$APP_HOME/scripts/${file##*/}"
done

if [ ! -f "$CONFIG_FILE" ]; then
  install -m 600 "$ROOT/config.example.sh" "$CONFIG_FILE"
  echo "Created $CONFIG_FILE"
else
  echo "Preserved existing $CONFIG_FILE"
fi

if [ ! -f "$RULES_FILE" ]; then
  install -m 600 "$ROOT/rules.example.md" "$RULES_FILE"
  echo "Created $RULES_FILE"
else
  echo "Preserved existing $RULES_FILE"
fi

escape_replacement() {
  printf '%s' "$1" | /usr/bin/sed 's/[&|]/\\&/g'
}

APP_ESCAPED="$(escape_replacement "$APP_HOME")"
CONFIG_ESCAPED="$(escape_replacement "$CONFIG_FILE")"

/usr/bin/sed \
  -e "s|__APP_HOME__|$APP_ESCAPED|g" \
  -e "s|__CONFIG_FILE__|$CONFIG_ESCAPED|g" \
  "$ROOT/claude/skills/file-inbox-assistant/SKILL.md" \
  > "$CLAUDE_HOME/skills/file-inbox-assistant/SKILL.md"
chmod 600 "$CLAUDE_HOME/skills/file-inbox-assistant/SKILL.md"

/usr/bin/sed \
  -e "s|__APP_HOME__|$APP_ESCAPED|g" \
  -e "s|__CONFIG_FILE__|$CONFIG_ESCAPED|g" \
  "$ROOT/claude/commands/sort-file-inbox.md" \
  > "$CLAUDE_HOME/commands/sort-file-inbox.md"
chmod 600 "$CLAUDE_HOME/commands/sort-file-inbox.md"

/usr/bin/sed \
  -e "s|__APP_HOME__|$APP_ESCAPED|g" \
  -e "s|__CONFIG_FILE__|$CONFIG_ESCAPED|g" \
  "$ROOT/swiftbar/file-inbox-assistant.10s.sh" \
  > "$PLUGIN_DIR/file-inbox-assistant.10s.sh"
chmod 755 "$PLUGIN_DIR/file-inbox-assistant.10s.sh"

# shellcheck disable=SC1090
. "$CONFIG_FILE"
mkdir -p "$INBOX" "$PENDING" "$BACKLOG" "$ARCH_ROOT" "$STATE_DIR"

missing=""
for command_name in jq tmux claude; do
  command -v "$command_name" >/dev/null 2>&1 || missing="$missing $command_name"
done

echo
echo "File Inbox Assistant installed."
echo "  Inbox:        $INBOX"
echo "  Archive root: $ARCH_ROOT"
echo "  Rules:        $RULES_FILE"
echo "  SwiftBar:     $PLUGIN_DIR/file-inbox-assistant.10s.sh"

if [ -n "$missing" ]; then
  echo
  echo "Missing required commands:$missing"
  echo "Install them before starting the workflow."
fi

echo
echo "Next steps:"
echo "  1. Edit $RULES_FILE"
echo "  2. Grant Full Disk Access to your terminal and SwiftBar if needed"
echo "  3. Run: bash $APP_HOME/scripts/start-session.sh"
echo
echo "Optional alias:"
echo "  alias file-inbox='bash \"$APP_HOME/scripts/start-session.sh\"'"
