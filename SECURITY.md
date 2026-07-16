# Security Policy

## Supported version

Security fixes are applied to the latest release.

## Reporting

Do not open a public issue containing private file names, paths, document
contents, credentials, or migration ledgers. Use GitHub private vulnerability
reporting when available, or provide a minimal reproduction containing only
synthetic data.

## Data handling

This project has no telemetry and does not upload its ledger. Claude Code may
send file content to the configured model service when classification requires
content inspection. Users are responsible for reviewing the service terms and
for keeping sensitive material outside the automated inbox.

The move layer rejects destinations outside the configured archive root, never
overwrites an existing item, and defaults undo operations to dry-run mode.
