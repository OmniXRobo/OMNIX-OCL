# OMNIX OCL — Milestone 1: Strategy Reconstruction Report

Version 0.1 · 2026-11-04 · OMNIX Global AI

## 0. Scope and limits of the evidence

- **No screenshot files were attached** to the request. This report uses only the observations the owner transcribed into the master prompt (trade times, one pending-order pair, four price outcomes, order counts, one commission total, the contract specification).
- The transcribed sample is small: 11 complete trades over about 17 minutes on 2026-11-04, plus one trade whose open time is missing. Anything inferred from it is a hypothesis, not a measurement of the reference robot.
- The decisive data source is the **MT5 Orders and Deals history** of the account that ran the reference robot. `MQL5/Scripts/OMNIX_OCL_ExportHistory.mq5` exports it (read-only), and `research/reconstruct_lifecycle.py` turns it into the lifecycle analysis the prompt asks for (Sections 3–5). Running those two tools on the real history is the first action item; it will confirm or reject most hypotheses below.
- Nothing here describes HexaFX's internal code. OMNIX OCL is engineered independently; the reference is only a behaviour to compare against.

Numbers in this report are produced by `research/analyze_evidence.py` (output in `research/evidence_analysis.md`).

## 1. Evidence table

### 1a. Confirmed observations (directly visible in the transcribed data)

| # | Observation | Source |
|---|---|---|
| C1 | Instrument XAUUSD; contract 100 oz; min lot 0.01; step 0.01; tick 0.01; tick value $1/lot; floating spread; market execution | contract spec |
| C2 | Entries are Buy Stop and Sell Stop pending orders; both sides armed at the same time | pending-order screenshot |
| C3 | Bracket: Buy Stop 4043.95 (SL 4042.95), Sell Stop 4041.88 (SL 4042.88), 0.11 lots each | pending-order screenshot |
| C4 | Initial SL distance is exactly $1.00 on both sides; no TP visible | C3, price outcomes |
| C5 | Both directions traded; 6 direction changes in 11 consecutive trades | timing table |
| C6 | Positions are strictly sequential in the sample: 0 overlaps | timing table |
| C7 | Duration 1–121 s (median 24 s, mean 41.6 s) | timing table |
| C8 | Re-entry gap 1–139 s (median 36 s); not a fixed interval | timing table |
| C9 | A losing trade lost exactly the $1.00 SL distance (-$11.00 at 0.11) | price outcomes |
| C10 | Winners captured +$0.28, +$0.39, +$0.48 (mean $0.38); gross P/L matches 100 oz × lots exactly | price outcomes |
| C11 | Some trades closed with final SL equal to close price | owner's note |
| C12 | Volumes 0.11 and 0.18 occur | owner's note |
| C13 | Period totals: 2,548 filled orders, 1,273 canceled, 3,821 total | history summary |
| C14 | Gross $7,143.78, commission -$3,433.32 (48.1% of gross), net $3,710.46 | history summary |

### 1b. Reasonable hypotheses (consistent with the data, not proven)

| # | Hypothesis | Support | What would refute it |
|---|---|---|---|
| H1 | **The bracket is centred on the market when armed.** With Bid 4042.85 / Ask 4042.98 (spread 0.13) and an offset of $0.97 from Ask/Bid, the observed prices are reproduced to the cent. Both SLs then sit within $0.04 of the arming mid-price. | Exact reproduction in `tests/python/test_ocl_reference.py` | Export shows `bid/ask_at_setup` far from the bracket centre |
| H2 | **One cancel per trade cycle.** 2,548 filled = 1,274 entry fills + 1,274 exit fills (SL exits are listed as filled orders); 1,273 cancels ≈ one unfilled bracket side per cycle. | Ratio 2.0016 | Export shows many cancels per filled entry |
| H3 | **Following price, if it happens, uses MODIFY, not cancel/replace.** Cancel/replace would inflate the cancel count far above one per cycle (H2). | H2 | Same as H2 |
| H4 | **The geometry itself prevents overlap.** The long's SL (4042.95) is above the Sell Stop (4041.88), so price must stop out the long before the sell can fill. That holds whether the opposite order is canceled at fill or kept. | C3, C6 | Export shows both sides filled with overlapping positions |
| H5 | **The 1-second Buy→Sell flip at 11:19:47/48 came from an already-resting Sell Stop** (opposite kept while the long was open, or re-armed instantly in a fast move). | C8 | Export shows the sell order's setup time after 11:19:47 |
| H6 | **Profitable exits are stop exits from a trailing or break-even stop**, with no TP. Exits at +$0.28 to +$0.48 with SL equal to close price fit a trail of roughly $0.1–0.2 behind price, activated after a small favourable move. | C10, C11 | Export shows exit deal reason EXPERT/CLIENT rather than SL |
| H7 | **Entries are tick-driven, not bar-close driven.** Open times fall at arbitrary seconds; durations as short as 1 s. | C7, C8 | — (weak evidence either way) |
| H8 | **Volumes changed over the period.** Commission per cycle is $2.695, implying average lots of 0.90 ($3/lot round turn) or 0.45 ($6/lot); neither equals 0.11–0.18. | C14 | Deals export with per-deal volumes and commission |

### 1c. Unknown parameters (cannot be read from the data supplied)

- Exact entry offset rule: fixed dollars, spread-scaled, volatility-scaled (ATR, tick range), or something else.
- Whether, how often, and by how much pending orders follow price.
- When the opposite order is canceled: at fill, at position close, or by another rule (H4 makes both look identical in the sample).
- Pending order lifetime or expiry rule.
- Trailing activation distance, trailing distance, step; whether break-even is used.
- Re-arm conditions: cooldown, spread gate, volatility gate, momentum gate.
- Session filter, news filter, maximum spread.
- Lot-sizing rule (fixed versus equity-based) and why 0.11 and 0.18 appear.
- Actual commission schedule (per side or per round turn; charged at entry, exit, or both).
- Win rate, MFE/MAE distribution, and how the net result varies by session or volatility.

## 2. Answers to the Section 3 classification question

| Candidate model | Verdict from current evidence |
|---|---|
| 1. Straddle breakout | **Most consistent.** Symmetric bracket around price (H1), both directions traded (C5). |
| 2. Price-following pending orders | Possible; if present it must use MODIFY (H3). Unproven. |
| 3. Volatility-based placement | Unknown; one bracket cannot show whether the $0.97 offset scales with volatility. |
| 4. Dynamic Buy/Sell Stop repositioning | Same as 2. |
| 5. Tick-based breakout execution | Consistent (H7). |
| 6. Microtrend momentum scalping | Exit profile (small trailing gains, $1 stop) fits momentum continuation after the breakout; entry is symmetric, so direction is not predicted in advance. |
| 7. Adaptive bid/ask distance | Offset measured from Ask (buy) and Bid (sell) reproduces the bracket (H1). Adaptivity unknown. |
| 8. OCO-style management | Yes in effect: one side fills and the other ends canceled (H2). Timing of the cancel is unknown. |

Working model: **a tick-driven symmetric stop bracket, about $1 from the market, $1 initial stop, a tight trailing stop that locks small gains, one position at a time, and the unfilled side canceled once per cycle.** OMNIX OCL implements this as its baseline and makes every unknown a configurable, testable parameter.

## 3. The economics this shape implies

The trade shape is a high-win-rate, small-winner, larger-loser profile. Break-even win rates for the observed shape (from `research/evidence_analysis.md`):

| Average winner | SL | Round-turn cost | Win rate needed to break even |
|---|---|---|---|
| $0.30 | $1.00 | $3/lot | 79.2% |
| $0.38 | $1.00 | $3/lot | 74.5% |
| $0.38 | $1.00 | $6/lot | 76.6% |
| $0.50 | $1.00 | $6/lot | 70.7% |

Consequences for the design:

1. **Costs decide the outcome.** In the reference period commission took 48% of pre-commission profit. A broker with $1–2/lot more cost, or 0.05–0.10 more average slippage on stop entries, can turn the same logic from profitable to losing. OMNIX OCL measures commission, spread and slippage per trade and reports net only.
2. **Stop-entry slippage matters.** A Buy Stop fills at the Ask after a breakout, often worse than the order price in fast markets. The EA logs requested vs executed price for every fill.
3. **Loss streaks are the risk.** With a ~75% break-even win rate, a few extra $1.00 losses wipe out many small wins. Consecutive-loss and daily-loss limits are therefore first-class controls.
4. **High win rate is not evidence of profit.** Reports lead with net expectancy and profit factor after costs.

## 4. Data requested from the owner

1. The original screenshots (to verify transcription and look for detail not transcribed).
2. On the account that ran the reference robot: run `OMNIX_OCL_ExportHistory.mq5` (Comment filter `HexaFX`, `Lookup ticks` on) and send `MQL5/Files/OMNIX_OCL/history_orders.csv` and `history_deals.csv`.
3. The Equiti contract-specification window for the gold symbol and the commission schedule page.
4. If available, the terminal Journal/Experts log for one trading day while the reference robot ran (only source for order modifications).

With item 2, run:

```
python3 research/reconstruct_lifecycle.py path\to\MQL5\Files\OMNIX_OCL --out research/lifecycle_report.md
```

It answers: filled/canceled ratio by type, pending lifespan, placement offset vs Bid/Ask, SL distance, bracket pairing, whether the opposite order is canceled at fill or at close, overlap, durations, re-entry gaps, exit reasons (SL in profit = trailing), and commission per lot on entry vs exit deals.
