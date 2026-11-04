# Evidence analysis (auto-generated)

Source: observations transcribed in the owner's prompt. The original screenshots and the
MT5 Orders/Deals export were not available to this analysis.

## 1. Trade timing

| # | Dir | Open | Close | Duration (s) | Gap from previous close (s) |
|---|---|---|---|---|---|
| 1 | Sell | 11:05:48 | 11:06:07 | 19 |  |
| 2 | Sell | 11:06:19 | 11:06:39 | 20 | 12 |
| 3 | Sell | 11:07:20 | 11:07:58 | 38 | 41 |
| 4 | Buy | 11:08:31 | 11:08:55 | 24 | 33 |
| 5 | Buy | 11:10:24 | 11:10:48 | 24 | 89 |
| 6 | Sell | 11:11:04 | 11:12:45 | 101 | 16 |
| 7 | Buy | 11:15:04 | 11:15:59 | 55 | 139 |
| 8 | Buy | 11:16:15 | 11:18:16 | 121 | 16 |
| 9 | Buy | ? | 11:19:47 |  |  |
| 10 | Sell | 11:19:48 | 11:19:49 | 1 | 1 |
| 11 | Buy | 11:20:29 | 11:21:12 | 43 | 40 |
| 12 | Sell | 11:22:46 | 11:22:58 | 12 | 94 |

- Durations: n=11, min=1s, median=24s, mean=41.6s, max=121s
- Re-entry gaps: n=10, min=1s, median=36s, mean=48.1s, max=139s
- Overlapping positions in sample: 0 (positions are strictly sequential here)
- Direction after each close: S->S, S->S, S->B, B->B, B->S, S->B, B->B, B->B, B->S, S->B, B->S

- Direction changes between consecutive trades: 6 of 11

## 2. Pending order geometry (single screenshot)

- Buy Stop 4043.95 SL 4042.95 (SL distance 1.00)
- Sell Stop 4041.88 SL 4042.88 (SL distance 1.00)
- Entry gap 2.07; midpoint 4042.915; each entry is 1.035 from the midpoint
- Buy SL sits +0.035 from midpoint, Sell SL -0.035: both stops land within 0.04 of the midpoint, i.e. close to where price was when the bracket was armed.
- If the bracket was placed around the then-current price with spread s, the offset from Ask (buy) / Bid (sell) was 1.035 - s/2:
  - spread 0.10 -> offset 0.985
  - spread 0.20 -> offset 0.935
  - spread 0.30 -> offset 0.885
  - spread 0.40 -> offset 0.835

## 3. Price outcomes

| Dir | Entry | Exit | Move ($) | Lots | Computed gross | Stated gross | Match |
|---|---|---|---|---|---|---|---|
| Sell | 4044.15 | 4045.15 | -1.00 | 0.11 | -11.00 | -11.00 | yes |
| Buy | 4044.37 | 4044.65 | +0.28 | 0.11 | +3.08 | +3.08 | yes |
| Sell | 4043.62 | 4043.23 | +0.39 | 0.11 | +4.29 | +4.29 | yes |
| Buy | 4042.94 | 4043.42 | +0.48 | 0.11 | +5.28 | +5.28 | yes |

- Mean favourable move on the 3 winners: $0.383 per oz; loss sample: exactly $1.00 (= initial SL).

## 4. Order counts and commissions

- Filled 2548, canceled 1273, total 3821; filled/canceled = 2.0016
- If each trade cycle = 1 entry fill + 1 exit fill (SL/close orders are listed as filled orders in MT5),
  cycles = 1274, which is within 1 of the canceled count (1273).
  This fits exactly ONE canceled order per trade: the unfilled side of a bracket.
  It does not fit frequent cancel-and-replace repositioning (that would create many more cancels);
  any following of price would then have to use order MODIFY, which creates no new tickets.
- Net 3710.46; commission = 48.1% of pre-commission profit
- Commission per cycle (if 1274 cycles): $2.695
- Pre-commission profit per cycle: $5.607; net per cycle $2.912
  - implied average lots if round-turn commission is $3.0/lot: 0.898
  - implied average lots if round-turn commission is $6.0/lot: 0.449
  - implied average lots if round-turn commission is $7.0/lot: 0.385
  None of these equal 0.11-0.18, so either volumes grew over the period, the period includes other sizes, or the commission schedule differs from $3/lot. Needs the Deals export to settle.

## 5. Break-even win rate for the observed trade shape

Loss = SL distance + slippage + cost; win = average favourable exit - cost (all per oz).

| Avg win ($) | SL ($) | Cost per RT ($/oz) | Break-even win rate |
|---|---|---|---|
| 0.30 | 1.00 | 0.03 | 79.2% |
| 0.30 | 1.00 | 0.06 | 81.5% |
| 0.38 | 1.00 | 0.03 | 74.5% |
| 0.38 | 1.00 | 0.06 | 76.6% |
| 0.50 | 1.00 | 0.03 | 68.7% |
| 0.50 | 1.00 | 0.06 | 70.7% |

$0.03/oz = $3/lot round turn; $0.06/oz = $6/lot round turn. Spread is paid separately via stop entry at Ask/Bid.
