---
name: file-inbox-assistant
description: Safely classify and archive files from a configured local inbox according to user-owned rules. Uses a constrained move script, confidence gating, a JSONL ledger, and dry-run-first undo.
user_invocable: true
---

# File Inbox Assistant

Process stable top-level entries from the configured file inbox. Read the
user's rules, inspect only the minimum content needed for classification, and
perform every filesystem change through the constrained move script.

## Fixed paths

- Application scripts: `__APP_HOME__/scripts`
- Configuration: `__CONFIG_FILE__`

Read the configuration first to obtain `INBOX`, `PENDING`, `ARCH_ROOT`,
`RULES_FILE`, and `CONFIDENCE_THRESHOLD`. Then read `RULES_FILE`.

## Hard safety constraints

1. Never call `mv`, `cp`, `rm`, `ditto`, or another write command directly.
2. Every move or park operation must use `archive-move.sh`.
3. Never overwrite an item or merge folders.
4. Keep every destination inside `ARCH_ROOT`.
5. Preserve the original base name inside `【original-name】`.
6. Treat folders and macOS bundles as indivisible units.
7. If confidence is below the configured threshold, park the item.
8. If the scan marks an item as `sensitive=true`, do not read its contents.
   Park it immediately and explain that manual secure handling is required.
9. Do not expose file contents, paths, or ledger data outside this task.

## Command discipline

Use one explicit command per item. Write literal absolute paths for every
argument. Do not use shell variables, loops, command substitution, or globs in
tool calls.

- Start batch: `__APP_HOME__/scripts/archive-move.sh --op start`
- Scan inbox: `__APP_HOME__/scripts/scan.sh`
- Finish batch: `__APP_HOME__/scripts/archive-move.sh --op finish`

## Workflow

1. Run `archive-move.sh --op start`.
2. Read the configuration and classification rules.
3. Run `scan.sh`.
4. Skip entries with `stable=false`; report them as still being written.
5. For `sensitive=true`, do not open the file. Park it with a clear reason.
6. For each other item, inspect the minimum useful content and metadata:
   - PDF: first pages through `pdftotext`, plus `pdfinfo` when available.
   - Text, Markdown, CSV, and supported documents: read a small relevant part.
   - Images or unsupported formats: use file name and metadata.
   - Folder: inspect at most two directory levels and relevant README files.
7. Apply only the destinations and naming rules in `RULES_FILE`.
8. Assign confidence from 0 to 1 and write one concrete reason.
9. At or above the threshold, call:

   ```text
   __APP_HOME__/scripts/archive-move.sh --op move \
     --src "<absolute inbox path>" \
     --dst-dir "<absolute directory inside ARCH_ROOT>" \
     --new-name "<normalized name with 【original】 and extension>" \
     --category "<relative category>" \
     --confidence <0-1> \
     --reason "<short evidence-based reason>" \
     --batch "<batch ID>" \
     --wrap off
   ```

10. Below the threshold, call:

    ```text
    __APP_HOME__/scripts/archive-move.sh --op park \
      --src "<absolute inbox path>" \
      --confidence <0-1> \
      --reason "<what is uncertain>" \
      --batch "<batch ID>"
    ```

11. Scan once more for items that arrived during processing.
12. Always run `archive-move.sh --op finish`, including after an error.
13. Report moved, parked, skipped, and failed items without reproducing private
    document contents.

## Default naming fallback

When `RULES_FILE` does not define a more specific pattern, use:

```text
YYYY-MM-DD_topic【original-name】.ext
```

Use a reliable document date when available; otherwise use the current date.
Keep the topic concise and concrete. Never invent missing people, projects, or
dates. If a reliable name cannot be produced, park the item.
