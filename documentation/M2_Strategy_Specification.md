# OMNIX OCL — Milestone 2: Strategy Specification

Version 0.3 · 2026-11-04 · applies to `MQL5/Experts/OMNIX_OCL.mq5` v0.3.0

This specification turns the Milestone 1 working model into explicit, configurable rules. Every unknown from the reconstruction report is an input, so the Strategy Tester and the demo account decide between alternatives, not assumptions. Input names are given in `code`.

## 1. Processing model

- **Event-driven, tick-level.** `OnTick` and a 250 ms `OnTimer` both call one `Process()` routine. A repeated quote is reprocessed at most once per second (for time exits and session ends). No logic waits for a bar close.
- **Stateless reconciliation.** Each pass rebuilds the EA's positions and orders from the terminal by magic number and symbol. A restart of MT5 or the VPS resumes management of whatever exists (`RECONCILE` log row).
- **`OnTradeTransaction`** records every order add/update/delete, SL change and deal, applies the OCO rule the moment an entry deal arrives, and books each closed position with its real commission.
- **Indicators read closed bars only** (shift 1), so the tester has no look-ahead.

Order of checks on every pass:

1. Continuous risk limits (emergency, daily loss, daily/weekly drawdown). A breach flattens and halts.
2. Volatility circuit breaker (60 s range above `InpCircuitRange60s`).
3. If a position is open: apply the OCO rule, then exits (section 4). Stop.
4. Flat: session gate, news gate, hostile-spread gate (resting stops are removed when spread is abnormal).
5. Signal and filters (section 2), lot size (section 6), risk gate, re-entry policy (section 5).
6. Place missing bracket sides, follow or expire existing ones (section 3).

## 2. Entry rules

**Bracket.** Buy Stop at `Ask + offset`, Sell Stop at `Bid − offset`, each with a server-side SL `InpSLFixed` (default $1.00) away, no TP. Prices are rounded to tick size and pushed out to respect the broker stop and freeze levels plus `InpStopBuffer`.

**Offset modes** (`InpDistMode`), all clamped to [`InpOffsetMin`, `InpOffsetMax`]:

| Mode | Offset | Tests hypothesis |
|---|---|---|
| `DIST_FIXED` (0) | `InpOffsetFixed` (default 0.95) | H1: fixed distance (0.97 reproduces the observed bracket at 0.13 spread) |
| `DIST_SPREAD_SCALED` (1) | fixed + k × spread | distance adapts to Bid/Ask spread |
| `DIST_ATR` (2) | k × ATR(M1,14) | volatility-based placement |
| `DIST_TICK_RANGE` (3) | k × mid-price range over `InpRangeWindowMs` | tick-volatility placement |

**SL distance.** `InpSLFixed`; optionally `max(fixed, InpSLAtrK × ATR)`.

**Sides** (`InpArmSides`): both (straddle, default) · only the side of the last `InpMomentumWindowMs` move ≥ `InpMomentumMin` (microtrend) · only the side of the H1 EMA(20/50) bias.

**Optional filters** (all off by default except the extreme-regime block): ATR(M1) band, RSI(M1) band, ADX(M5) minimum, and no arming in the extreme volatility regime. Regime = ATR(M1,14) / ATR(M1,240): <0.6 quiet, <1.4 normal, <2.5 active, else extreme.

## 3. Pending order management and cancellation

| Rule | Inputs | Behaviour |
|---|---|---|
| Follow price | `InpPendingMode`: static (0) · modify (1) · cancel-and-replace (2) | Modify keeps the ticket, which matches H3 (one cancel per cycle). Replace is offered for brokers that reject modifies and as a test of the alternative. |
| Follow direction | `InpFollowDir`: tighten-only (0) · both ways (1) | Tighten-only moves the Buy Stop down when price falls and the Sell Stop up when price rises, so the bracket re-centres without running away from a breakout. |
| Follow throttle | `InpFollowStep`, `InpFollowMinMs`, `InpFollowMaxPerMin` | Limits server load and avoids excessive-modification flags. Orders inside the freeze level are never touched. |
| Lifetime | `InpPendingLifetimeS`, `InpBrokerExpiry` | Unfilled orders are canceled after N s; broker-side expiry is an optional backstop. |
| Withdraw side | automatic | A side the signal no longer wants (filter fails, momentum flips) is canceled. |
| Hostile conditions | `InpMaxSpread`, `InpMaxSpreadVsAvg`, no-new switch, emergency, session end, news blackout, circuit breaker | All resting stops are canceled. |
| Duplicates | automatic | Any extra order with our magic is canceled; a 3 s in-flight guard per side prevents double sends. |

**OCO policy** (`InpOcoMode`) — the three explanations of the observed cancel pattern:

| Mode | Opposite order after a fill | After the position closes |
|---|---|---|
| `OCO_CANCEL_ON_FILL` (0, default) | canceled immediately (also from `OnTradeTransaction`) | new bracket per re-entry policy |
| `OCO_CANCEL_ON_CLOSE` (1) | kept while the position is open | canceled at close |
| `OCO_KEEP_OPPOSITE` (2) | kept while the position is open | kept; becomes one side of the next bracket (H5) |

In modes 1 and 2 the opposite order is kept only while the position's SL lies strictly between the entry and the opposite order, so the position must be stopped out before the opposite can fill. If that geometry breaks, the opposite is canceled (`OCO geometry unsafe`). A same-side remainder after a partial fill is always canceled. On netting accounts, a kept opposite that fills closes the position rather than reversing it; mode 0 is recommended there.

## 4. Exit rules

A server-side SL always exists and only moves in the position's favour. If a position is found without an SL it is restored at once; if that fails twice the position is closed.

`InpExitProfile` selects a variant for testing; `EXIT_CUSTOM` combines the individual switches.

| Variant | Profile | Rule |
|---|---|---|
| A | `EXIT_A_FIXED` (1) | Initial SL only. |
| B | `EXIT_B_TRAIL` (2, default) | After a favourable move ≥ `InpTrailActivation` (0.30), SL = price − `InpTrailDistance` (0.15), moved only by ≥ `InpTrailStep`. Fits H6: +0.28 to +0.48 exits. |
| C | `EXIT_C_BREAKEVEN` (3) | After `InpBETrigger`, SL = entry + round-turn commission (as price) + `InpBEOffset`. |
| D | `EXIT_D_MICROPROFIT` (4) | Close at net floating profit ≥ `InpMicroProfitUSD` (after estimated commission and swap). |
| E | `EXIT_E_TIME` (5) | Close after `InpMaxHoldS`, always or only if not net-profitable (`InpTimeExitRule`). |
| F | `EXIT_F_ADAPTIVE` (6) | Break-even + time exit + trailing distance = max(`InpAdaptiveMinTrail`, k × recent range) + momentum-fade close when in net profit and the micro-move reverses by `InpMomentumMin`. |

When break-even and trailing both propose a stop, the tighter one is used. SL modifies are throttled (`InpSLMinModifyMs`) and skipped inside the freeze level.

## 5. Re-entry rules

After every close the EA records the time; a new bracket side may be placed only when `InpRearmCooldownS` has elapsed and the policy allows it. The reason for waiting or arming is logged on every state change (`WAIT` rows, and the `re-arm:` text on each placement).

| Mode | `InpRearmMode` | Arms when |
|---|---|---|
| 1 Immediate | 0 | cooldown elapsed |
| 2 Spread-controlled | 1 (default) | spread ≤ `InpRearmSpreadK` × average spread |
| 3 Volatility-controlled | 2 | mid-price range over the window within [`InpRearmRangeMin`, `InpRearmRangeMax`] |
| 4 Momentum-controlled | 3 | move over `InpMomentumWindowMs` ≥ `InpMomentumMin` |
| 5 Adaptive | 4 | regime picks the rule: quiet → volatility, normal → spread, active → momentum, extreme/unknown → wait |

There is no fixed 1-second rule. The observed 1–139 s gaps are an output to compare against, not an input.

## 6. Position sizing

| Mode | `InpLotMode` | Size |
|---|---|---|
| Fixed | 0 | `InpFixedLots` (default 0.01) |
| Risk | 1 | equity × `InpRiskPct` / (SL distance × money-per-$-per-lot + round-turn commission) |
| Adaptive | 2 | risk size × factors that are all ≤ 1: active regime 0.75, extreme/unknown 0.5, daily DD over half its limit 0.5, 2+ consecutive losses 0.5; capped at `InpAdaptiveMaxLots` |

In every mode the size is capped so that one SL hit plus commission cannot exceed `InpMaxRiskPct` of equity; if even the minimum lot exceeds it, nothing is placed. Money per $1 per lot is `tick value / tick size` read from the symbol, never assumed. Commission starts from `InpCommissionRTPerLot` and switches to the value learned from real deals after 5 closed trades. News reduced-risk mode multiplies the size by `InpNewsLotFactor`.

## 7. Risk limits (all enforced before submission; continuous ones every pass)

| Limit | Input | Default |
|---|---|---|
| Risk per trade cap | `InpMaxRiskPct` | 1.0 % |
| Daily loss (from day-start balance, incl. floating) | `InpMaxDailyLossPct` | 3 % → flatten, halt for the day |
| Daily drawdown from the day's equity peak | `InpMaxDailyDDPct` | 4 % → flatten, halt for the day |
| Weekly drawdown | `InpMaxWeeklyDDPct` | 8 % → flatten, halt for the week |
| Max spread / vs average | `InpMaxSpread`, `InpMaxSpreadVsAvg` | 0.40 / 2.5× |
| Max average entry slippage | `InpMaxSlippage` | 0.30 → stop arming |
| Concurrent positions / pending orders | `InpMaxPositions`, `InpMaxPending` | 1 / 2 |
| Entries per hour | `InpMaxTradesPerHour` | 0 (off, owner request) |
| Consecutive losses → pause | `InpMaxConsecLosses`, `InpConsecLossPauseMin` | off (0) by owner choice, 2026-11-04; set e.g. 4 → 30 min to enable |
| Order rejection rate (last 20) | `InpMaxRejectRate` | 50 % |
| Total open lots on the account (all symbols) | `InpMaxAccountLots` | 1.0 |
| Free margin after order / margin level | `InpMinFreeMargin`, `InpMinMarginLevel` | 100 / 300 % |
| Daily commission budget | `InpMaxDailyCommission` | off |
| Emergency stop | `InpEmergencyStop` or terminal global variable `OMNIX_OCL_EMERGENCY` > 0 | flatten and stop |
| Stop new orders | global variable `OMNIX_OCL_NO_NEW` > 0 | cancel pendings, keep managing positions |

Forbidden by design: martingale, grid, averaging down, size increases after losses, removing an SL. Live accounts: the EA refuses to initialise on any non-demo account (`OCL_LIVE_TRADING_ALLOWED false` in `Common.mqh`).

## 8. Sessions and news

- Session windows are in Dubai time (UTC+4, no DST): `InpSessionDubai` (default 24 h) and an optional second window. Preset `Equiti_Dubai_1800-1900.set` covers 18:00–19:00 Dubai.
- The broker's own trading sessions (`SymbolInfoSessionTrade`) are always respected, plus a delay after each session opens, a guard around the server midnight rollover, and a Friday cutoff.
- UTC on demo comes from the terminal clock. In the Strategy Tester (where it is not available) it is server time minus `InpServerUTCOffsetH` with the selected DST rule (US or EU), verified by unit tests for 2026 transitions.
- News: high-impact USD events from `Common\Files\OMNIX_OCL\news_calendar.csv` (tester and demo) and the MT5 economic calendar (demo only). Blackout `InpNewsBeforeMin`/`InpNewsAfterMin`, with longer FOMC windows taken from the event's actual scheduled time. Actions: block new orders, reduced risk, or monitor only (default since 2026-11-04, owner choice: log the event and keep trading). The EA does not treat news as a directional signal.

## 9. Logging

`Common\Files\OMNIX_OCL\` on demo (`MQL5\Files\OMNIX_OCL\tester\` in the tester):

- `events_YYYYMMDD.csv`: every placement, modify, cancel, fill, SL change, close, error, risk rejection and wait-state change, with millisecond tick timestamp, broker, environment, masked account, symbol, version, tickets, Bid, Ask, spread, volume, requested and executed price, SL, commission, slippage, retcode and reason.
- `trades.csv`: one row per closed position with gross, commission, swap, net, entry slippage, exit reason, regime and strategy tag.
- `status.json`: dashboard snapshot. `broker_profile_<server>_<symbol>.txt`: broker profile including sessions.

## 10. Strategy Tester objective

`OnTester()` returns net profit / (1 + max equity drawdown), and a large penalty below 30 trades, so optimisation favours risk-adjusted net results over raw profit or win rate.
