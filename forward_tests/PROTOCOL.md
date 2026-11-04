# OMNIX OCL — Forward test protocol (Milestones 8–9)

Demo accounts only. Nothing in this folder is a result until a run produces logs.

| Stage | Duration | Pass condition |
|---|---|---|
| 1 Technical verification | 1–2 h of active market | Bracket placed, followed and canceled; at least one fill, SL trail and close; OCO rule applied; emergency and no-new switches work; restart of MT5 re-adopts positions/orders (`RECONCILE` row). |
| 2 Short observation | 48–72 h | No unhandled errors; rejection rate < 5 %; no duplicate orders; daily reset rows present. Not evidence of profitability. |
| 3 Extended | ≥ 20 active trading days | Net expectancy, PF, DD and cost breakdown computed from `trades.csv`; compared with the backtest of the same dates. |
| 4 Broker comparison | same dates on Equiti, Exness, MultiBank demos | Same EA version and logic; per-broker presets only change symbol, commission and server offset. |

For each run keep: EA version, preset file, broker server, `events_*.csv`, `trades.csv`, `broker_profile_*.txt`, and the MT5 account history export. Compare: net P/L, spread and commission per trade, entry slippage (requested vs executed), rejection rate, `EXEC_OK` latency, SL behaviour, trade frequency, drawdown.
