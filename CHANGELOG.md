# Changelog

## Unreleased
- Defaults changed at the owner's request: 0.01 lots, consecutive-loss pause off, news action monitor-only (all presets too).
- Default changed at the owner's request: max-trades-per-hour limit off (InpMaxTradesPerHour=0) in the EA and all presets. Daily loss and drawdown limits unchanged.
- Fix: a cached pending ticket that filled since the last scan is no longer cancelled (removes the remaining rc=10013 "same-side remainder" EXEC_FAIL).
- Fix: also skip a pending ticket that already opened a position (position id == order ticket), which MT5 still lists as PLACED for ~40 ms.
- Fix (slow links, e.g. Exness at ~350 ms): stop modifies keep an extra gap from price of InpLatencyPadPerSec x latency and are spaced at least two round trips apart. If price passes the wanted stop while the modify is in flight, the position is closed at market instead of waiting for the old, worse stop.
- Exness.set: commission 0 and symbol notes from the 474869353 demo, server time UTC confirmed, wider trail (0.50/0.30) plus break-even 0.25. Not validated on Exness data yet.

## 0.3.0 - 2026-11-04
- Milestone 1 evidence analysis and reconstruction report; history export script and lifecycle reconstruction tool.
- Milestone 2 strategy specification.
- Milestone 3 EA source: broker discovery/profile, logging, market data, sessions/news, risk manager, execution engine,
  signal engine, pending-order bracket with three OCO modes, exit variants A-F, presets for Equiti/Exness/MultiBank.
- Offline tests: 73 pytest checks, MQL5 lint. Not yet compiled in MetaEditor.
