# OMNIX OCL — Backtest and validation plan (Milestones 6–7)

No backtest has been run yet. This file defines how they will be run so results are reproducible and not overfit. Every run is recorded in `backtests/RESULTS_LOG.md` (EA version, preset file, symbol, broker server, date range, modelling, tick-data quality %, net profit, commission, PF, max DD, trades).

## Data

- Every tick based on real ticks; record the tester's "History quality" percentage for each run.
- At least 12 months; label each month by regime afterwards from ATR and trend (trending, ranging, high/low volatility, news-heavy).
- Commission: confirm the tester applies the account's real commission. If not, add the difference from `trades.csv` in post-processing and say so in the result.

## Periods (example with data to 2026-10-31)

| Segment | Use |
|---|---|
| 2025-11-01 → 2026-04-30 | In-sample: structural comparisons and tuning |
| 2026-05-01 → 2026-07-31 | Out-of-sample 1: no tuning allowed |
| 2026-08-01 → 2026-10-31 | Out-of-sample 2: no tuning allowed |
| Walk-forward | 3-month optimise / 1-month test windows rolled monthly over the full year |

Also report 1-, 3-, 6- and 12-month runs of the chosen configuration.

## Order of comparisons

1. **Structure** (in-sample, defaults otherwise): exit variant A–F; OCO mode 0–2; re-arm mode 1–5; pending mode static/modify/replace; offset mode fixed/spread/ATR/range.
2. **Parameters** of the best structure only, coarse grids: offset 0.5–1.5 step 0.1; SL 0.6–1.6 step 0.2; trailing activation 0.15–0.6; trailing distance 0.08–0.30; spread cap; session window.
3. **Stability**: a parameter is accepted only if its neighbours (±1 grid step) are also net-positive with similar drawdown. Isolated peaks are rejected.
4. **Stress**: rerun the final configuration with the tester's random execution delay, with commission +$2/lot, and with the max spread cap removed, to show sensitivity to costs.

## Acceptance for moving to demo

- Net profit > 0 after commission in both out-of-sample segments and in ≥ 60 % of walk-forward windows.
- Net profit factor ≥ 1.15; max equity drawdown within the daily/weekly limits' intent.
- ≥ 300 trades in the evaluated period.
- Result survives the +$2/lot commission stress, or the report says clearly that it does not.

These are thresholds for continuing, not promises of future results.
