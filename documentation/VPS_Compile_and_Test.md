# OMNIX OCL — Windows VPS: install, compile, test

The development environment used so far cannot run MetaTrader 5 or the MQL5 compiler (MetaQuotes downloads are blocked there). **The EA has not been compiled yet.** These steps do that on your VPS. Please send back the outputs listed under "What to send back".

## 1. Install the files

1. In MT5: **File → Open Data Folder**. This opens `...\MetaQuotes\Terminal\<ID>\`.
2. Copy from this project into that folder, keeping the paths:
   - `MQL5\Experts\OMNIX_OCL.mq5` → `MQL5\Experts\`
   - `MQL5\Include\OMNIX_OCL\*.mqh` → `MQL5\Include\OMNIX_OCL\`
   - `MQL5\Scripts\*.mq5` and `MQL5\Scripts\OMNIX_OCL_TestVectors.mqh` → `MQL5\Scripts\`
   - `MQL5\Presets\*.set` → `MQL5\Presets\`
3. Optional news file: copy `research\news_calendar_template.csv` to `%APPDATA%\MetaQuotes\Terminal\Common\Files\OMNIX_OCL\news_calendar.csv` and fill in real event times (UTC) from the official calendars.

## 2. Compile

GUI: open MetaEditor (F4), open `Experts\OMNIX_OCL.mq5`, press **F7**. The Errors tab must show `0 errors`. Repeat for `Scripts\OMNIX_OCL_UnitTests.mq5` and `Scripts\OMNIX_OCL_ExportHistory.mq5`.

Command line (PowerShell, adjust the two paths):

```powershell
$ME   = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$DATA = "$env:APPDATA\MetaQuotes\Terminal\<ID>"
& $ME /compile:"$DATA\MQL5\Experts\OMNIX_OCL.mq5" /log:"$DATA\ocl_compile.log" /inc:"$DATA\MQL5"
& $ME /compile:"$DATA\MQL5\Scripts\OMNIX_OCL_UnitTests.mq5" /log:"$DATA\ocl_tests_compile.log" /inc:"$DATA\MQL5"
Get-Content "$DATA\ocl_compile.log"; Get-Content "$DATA\ocl_tests_compile.log"
```

If there are compile errors, send the log; I will fix and resend.

## 3. Unit tests inside MT5

Drag **Scripts → OMNIX_OCL_UnitTests** onto any chart. The Experts tab prints `OMNIX OCL unit tests: N passed, 0 failed`; details are in `MQL5\Files\OMNIX_OCL\unit_test_results.txt`. These are the same 66 vectors (plus 3 bracket checks) that pass in Python, so any failure points to an MQL5-specific difference.

## 4. Export the reference robot's history (Milestone 1 evidence)

On the account that ran the reference robot:

1. Drag **Scripts → OMNIX_OCL_ExportHistory** onto an XAUUSD chart.
2. Inputs: `InpFrom` = start of the period in the screenshots, `InpCommentFilter` = `HexaFX`, `InpLookupTicks` = true.
3. Send `MQL5\Files\OMNIX_OCL\history_orders.csv` and `history_deals.csv`.

The script is read-only; it never sends or changes orders.

## 5. Strategy Tester — first smoke test

**View → Strategy Tester** (Ctrl+R):

| Setting | Value |
|---|---|
| Expert | `OMNIX_OCL` |
| Symbol | your gold symbol (XAUUSD / XAUUSDm / GOLD …) |
| Timeframe | M1 (logic is tick-driven; timeframe only sets the visual chart) |
| Date | last 1 month first |
| Modelling | **Every tick based on real ticks** |
| Deposit / leverage | your intended demo balance, account leverage |
| Execution delay | "Random delay" for realism after the first run |
| Inputs | Load `Equiti.set` (right-click on Inputs → Load) |

Check after the run:

- Journal: no `INIT_REJECT` and no repeated `EXEC_FAIL` rows.
- `MQL5\Files\OMNIX_OCL\tester\events_*.csv`: `PLACE`, `FILL`, `MODIFY SL`, `CANCEL`, `POSITION_CLOSED` rows present.
- `trades.csv`: one row per position; `commission` non-zero if your account charges it.
- Tester **Backtest** tab: net profit, profit factor, max drawdown, total trades.

Note: the tester's commission comes from the broker's server settings for the symbol; if the tester shows zero commission while your account charges it, results are optimistic. Compare against `trades.csv` and tell me.

## 6. Exit-variant and OCO comparison (after the smoke test passes)

Use **Optimization: Slow complete algorithm**, criterion **Custom max** (uses `OnTester()`), and optimise only one group at a time:

1. `InpExitProfile` 1..6 (all six exit variants).
2. `InpOcoMode` 0..2.
3. `InpRearmMode` 0..4.
4. `InpPendingMode` 0..2.

Use the **Forward** option = 1/3 so the last third is out-of-sample. Export each result table (right-click → Export to XML) and send them. Do not tune entry/SL/trailing distances until these structural comparisons are done; see `backtests/TEST_PLAN.md`.

## 7. Demo forward test (Stage 1 technical verification)

1. Log in to the **Equiti demo** account.
2. Tools → Options → Expert Advisors: allow algorithmic trading.
3. Attach `OMNIX_OCL` to an XAUUSD M1 chart, load `Equiti.set`, enable "Allow Algo Trading".
4. The EA refuses to start on a real account; this is intentional.
5. Watch for 1–2 hours: the chart comment shows state; `Common\Files\OMNIX_OCL\events_*.csv` grows.
6. Emergency stop: Tools → Global Variables (F3) → set `OMNIX_OCL_EMERGENCY` to 1. Stop new orders only: set `OMNIX_OCL_NO_NEW` to 1.

## What to send back

1. Compile logs (or "0 errors" screenshots).
2. Unit test result line.
3. `history_orders.csv` and `history_deals.csv` from the reference account.
4. First tester run: the Backtest report (right-click → Report → HTML) and `tester\trades.csv`, `tester\events_*.csv`.
5. The `broker_profile_*.txt` file from each broker.
