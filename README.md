# OMNIX OCL — Order Control & Liquidity

**Powered by OMNIX Global AI** · MetaTrader 5 Expert Advisor for XAUUSD · v0.3.0 · **Demo and Strategy Tester only**

OMNIX OCL is a tick-driven gold scalper built around a Buy Stop / Sell Stop bracket with configurable OCO, re-entry, exit and sizing variants. It is engineered independently. Observed behaviour of a third-party robot was used only to decide which alternatives to make testable.

## Status (be precise)

| Milestone | State | Evidence |
|---|---|---|
| 1 Evidence analysis | Done on the transcribed observations; **original screenshots and the MT5 Orders/Deals export not yet received** | `reports/M1_Strategy_Reconstruction_Report.md`, `research/evidence_analysis.md` |
| 2 Strategy specification | Done | `documentation/M2_Strategy_Specification.md` |
| 3 MQL5 foundation | Source written; **not yet compiled** (no MT5/MetaEditor in the build environment) | `MQL5/`, `documentation/VPS_Compile_and_Test.md` |
| 4 Order management | Implemented in source, unverified until compiled and run | `PendingOrders.mqh`, `ExecutionEngine.mqh` |
| 5 Position management | Implemented in source, unverified until compiled and run | `PositionManager.mqh` |
| 6–12 | Not started: need compile, tick data and demo accounts | `backtests/TEST_PLAN.md`, `forward_tests/PROTOCOL.md` |

No backtest or forward-test results exist yet. None are claimed.

## Layout

```
MQL5/Experts/OMNIX_OCL.mq5             EA entry point, inputs, main loop, OnTradeTransaction
MQL5/Include/OMNIX_OCL/
  OCLMath.mqh          pure price/volume/time maths (mirrored and tested in Python)
  Common.mqh           enums, version, live-trading lock
  BrokerProfile.mqh    gold symbol discovery, symbol/broker validation, profile file
  MarketData.mqh       tick buffer, spread stats, M1/M5/H1 indicators, volatility regime
  SessionNews.mqh      Dubai-time sessions, broker sessions, DST, news blackout, FOMC
  SignalEngine.mqh     bracket distance, side selection, filters, re-entry policies
  PendingOrders.mqh    bracket placement, follow/expire, OCO policies, duplicate guard
  PositionManager.mqh  exit variants A-F, SL restore, excess-position guard
  RiskManager.mqh      sizing modes and every risk limit
  ExecutionEngine.mqh  validated requests, retcodes, filling fallback, back-off
  TradeLogger.mqh      events CSV, trades CSV, status.json
MQL5/Scripts/OMNIX_OCL_UnitTests.mq5   runs the shared test vectors inside MT5
MQL5/Scripts/OMNIX_OCL_ExportHistory.mq5  read-only Orders/Deals export for research
MQL5/Presets/          Equiti, Exness, MultiBank, Equiti 18:00-19:00 Dubai
research/              evidence data, analysis, lifecycle reconstruction tool
tests/                 Python mirror + vectors, lifecycle test, preset checks, MQL5 lint
backtests/ forward_tests/ reports/ documentation/
```

`analytics/` and `dashboard/` are intentionally empty until real logs exist (Milestone 10).

## Quick start

1. Offline checks (any machine with Python 3 and pytest): `./run_tests.sh`
2. VPS: follow `documentation/VPS_Compile_and_Test.md` (install, compile, unit tests, export, first tester run).

## Safety

- Refuses to start on any non-demo account (`OCL_LIVE_TRADING_ALLOWED false`). Enabling live trading needs an owner-approved code change.
- One position at a time by default; server-side SL always present and only tightened; no martingale, grid, averaging or loss-recovery sizing.
- Emergency stop: input `InpEmergencyStop` or terminal global variable `OMNIX_OCL_EMERGENCY` = 1.
- Logs never contain passwords; the account number is masked.

No strategy here is promised to be profitable. Results must come from the test plan.
