# Changelog

## Unreleased
- Defaults changed at the owner's request: 0.01 lots, consecutive-loss pause off, news action monitor-only (all presets too).
- Fix: a cached pending ticket that filled since the last scan is no longer cancelled (removes the remaining rc=10013 "same-side remainder" EXEC_FAIL).

## 0.3.0 - 2026-11-04
- Milestone 1 evidence analysis and reconstruction report; history export script and lifecycle reconstruction tool.
- Milestone 2 strategy specification.
- Milestone 3 EA source: broker discovery/profile, logging, market data, sessions/news, risk manager, execution engine,
  signal engine, pending-order bracket with three OCO modes, exit variants A-F, presets for Equiti/Exness/MultiBank.
- Offline tests: 73 pytest checks, MQL5 lint. Not yet compiled in MetaEditor.
