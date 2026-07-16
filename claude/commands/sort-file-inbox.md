---
description: Safely process the configured file inbox with File Inbox Assistant.
---

Use the **file-inbox-assistant** skill now.

1. Read `__CONFIG_FILE__` and its configured `RULES_FILE`.
2. Run `__APP_HOME__/scripts/archive-move.sh --op start`.
3. Run `__APP_HOME__/scripts/scan.sh`.
4. Process stable entries one at a time according to the skill and rules.
5. Use only `archive-move.sh` for filesystem changes.
6. Park sensitive or low-confidence items without reading sensitive contents.
7. Run `__APP_HOME__/scripts/archive-move.sh --op finish`.
8. Print a concise batch summary.
