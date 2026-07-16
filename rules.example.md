# File Inbox Rules

Edit this file before enabling automatic sorting. Every destination must stay
inside the archive root configured in `config.sh`.

## Decision order

1. Active work with a defined outcome or deadline -> `Projects/`.
2. Ongoing responsibilities without an end date -> `Areas/`.
3. Reusable references, templates, manuals, and learning material -> `Resources/`.
4. Completed or inactive material -> `Archive/`.
5. Personal documents that do not fit the categories above -> `Personal/`.
6. If the destination is ambiguous, use `_Needs Review`; do not guess.

## Suggested subfolders

```text
File Archive/
├── Projects/
├── Areas/
├── Resources/
├── Archive/
└── Personal/
```

You may replace this structure completely. Keep rules mutually exclusive and
include examples for categories that are easy to confuse.

## Naming

Default format:

```text
YYYY-MM-DD_topic【original-name】.ext
```

- Preserve the original base name inside `【】`.
- Keep the original extension at the end.
- Use the document date when reliable; otherwise use the current date.
- Use a short, concrete topic. Avoid labels such as `final`, `new`, or `misc`.
- Treat a folder as one unit; do not split it unless a user explicitly asks.

## Confidence

- `>= 0.80`: destination and name are supported by clear evidence.
- `< 0.80`: park in `_Needs Review` and explain what is uncertain.

## Sensitive material

Do not open or summarize files marked `sensitive=true`. Park them for manual
review and recommend a password manager or another appropriate secure system.
