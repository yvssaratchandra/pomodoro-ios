# Baseline schema v1 fixtures

These JSON files were generated with the unchanged `Models.swift`,
`TimerEngine.swift`, and `BackupService.swift` from baseline commit `70eb33b`, using
Swift 6.0.3. They are outputs of that version's actual encoder, not JSON produced
by the migration under test. Keep them unchanged when adding later schemas.

- `v1-history.json` is an idle backup with completed and interrupted work,
  a remembered duration, dark appearance, and muted alerts.
- `v1-running.json` is an on-device document with the same saved history and an
  active focus timer. It is deliberately invalid as an exported backup.

IDs and Foundation reference-date timestamps are fixed for reproducibility.
Fractional timestamps include `.125`, `.75`, `.5`, and `.875`; interrupted work
lasts 59.75 seconds. The fixtures contain no intention, privacy, or goal-history
fields because schema v1 did not define them.
