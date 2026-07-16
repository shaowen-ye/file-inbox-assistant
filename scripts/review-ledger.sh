#!/bin/bash
# Read-only ledger viewer and CSV exporter.
set -uo pipefail

CONFIG_FILE="${FILE_INBOX_CONFIG:-$HOME/.config/file-inbox-assistant/config.sh}"
[ -f "$CONFIG_FILE" ] || { echo "ERR: missing config: $CONFIG_FILE" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONFIG_FILE"

[ -n "$JQ_BIN" ] && [ -x "$JQ_BIN" ] || { echo "ERR: jq is required" >&2; exit 127; }

mode=recent
limit=20
batch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recent) mode="recent"; limit="${2:-20}"; shift 2 ;;
    --pending) mode="pending"; shift ;;
    --summary) mode="summary"; shift ;;
    --batches) mode="batches"; shift ;;
    --batch) mode="batch"; batch="${2:-}"; shift 2 ;;
    --all) mode="all"; shift ;;
    --csv) mode="csv"; shift ;;
    -h|--help) mode="help"; shift ;;
    *) echo "ERR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$mode" = help ]; then
  printf '%s\n' \
    "review-ledger.sh [--recent N|--pending|--summary|--batches|--batch ID|--all|--csv]"
  exit 0
fi

[ -f "$LEDGER" ] || { echo "No ledger found: $LEDGER"; exit 0; }
root="${ARCH_ROOT%/}/"

case "$mode" in
  recent)
    "$JQ_BIN" -rs --arg root "$root" --argjson count "$limit" '
      sort_by(.ts) | reverse | .[0:$count] | reverse | .[]
      | "[\(.ts[0:16] | gsub("T";" "))] \(.op)/\(.status) conf=\(.confidence)\n  \(.src_name)\n  -> \(.dst | sub($root;""))"
        + (if (.reason // "") != "" then "\n  reason: \(.reason)" else "" end) + "\n"
    ' "$LEDGER"
    ;;
  all)
    "$JQ_BIN" -rs --arg root "$root" '
      sort_by(.ts) | .[]
      | "[\(.ts[0:16] | gsub("T";" "))] \(.op)/\(.status) conf=\(.confidence)\n  \(.src_name)\n  -> \(.dst | sub($root;""))\n"
    ' "$LEDGER"
    ;;
  pending)
    "$JQ_BIN" -rs '
      map(select(.status=="pending" or .status=="duplicate")) | .[]
      | "[\(.ts[0:16] | gsub("T";" "))] \(.status): \(.dst_name)\n  \(.reason // "manual review required")\n"
    ' "$LEDGER"
    ;;
  summary)
    "$JQ_BIN" -rs '
      group_by(.batch) | sort_by(.[0].ts) | reverse | .[]
      | "\(.[0].batch): \(length) record(s), operations=\([.[].op] | unique | join(",")), statuses=\([.[].status] | unique | join(","))"
    ' "$LEDGER"
    ;;
  batches)
    "$JQ_BIN" -rs '[.[].batch] | unique | .[]' "$LEDGER"
    ;;
  batch)
    [ -n "$batch" ] || { echo "ERR: --batch requires an ID" >&2; exit 2; }
    "$JQ_BIN" -rs --arg batch "$batch" 'map(select(.batch==$batch)) | .[]' "$LEDGER"
    ;;
  csv)
    output="$STATE_DIR/ledger.csv"
    mkdir -p "$STATE_DIR"
    printf '\xEF\xBB\xBF' > "$output"
    "$JQ_BIN" -rs '
      ["timestamp","operation","status","category","destination","source","confidence","batch","reason"],
      (sort_by(.ts) | reverse | .[]
       | [.ts,.op,.status,.category,.dst,.src,(.confidence|tostring),.batch,.reason])
      | @csv
    ' "$LEDGER" >> "$output"
    echo "Exported: $output"
    command -v open >/dev/null 2>&1 && open "$output" || true
    ;;
esac
