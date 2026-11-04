"""
OMNIX OCL - Milestone 1 evidence analysis.

Reads the observations transcribed from the owner's MT5 screenshots and derives
timing, geometry, and cost figures. Every number here is computed from the
transcribed evidence only; nothing is invented. Output: research/evidence_analysis.md

Usage:  python3 research/analyze_evidence.py
"""
from __future__ import annotations

import csv
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = 100.0  # oz per lot, as observed in the Equiti contract spec screenshot


def t(s: str):
    return datetime.strptime(s, "%H:%M:%S") if s else None


def load_trades():
    rows = []
    with open(HERE / "evidence_observations.csv", newline="") as f:
        for r in csv.DictReader(f):
            rows.append({"dir": r["direction"], "open": t(r["open_time"]), "close": t(r["close_time"])})
    # order by the best known timestamp (open, else close)
    rows.sort(key=lambda r: r["open"] or r["close"])
    return rows


def timing(rows):
    out = []
    prev_close = None
    for r in rows:
        dur = (r["close"] - r["open"]).total_seconds() if r["open"] else None
        gap = (r["open"] - prev_close).total_seconds() if (r["open"] and prev_close) else None
        out.append({**r, "dur": dur, "gap": gap})
        prev_close = r["close"]
    return out


def stats(xs):
    xs = sorted(x for x in xs if x is not None)
    n = len(xs)
    med = xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2
    return {"n": n, "min": xs[0], "median": med, "mean": sum(xs) / n, "max": xs[-1]}


def main():
    rows = timing(load_trades())
    md = ["# Evidence analysis (auto-generated)", "",
          "Source: observations transcribed in the owner's prompt. The original screenshots and the",
          "MT5 Orders/Deals export were not available to this analysis.", "",
          "## 1. Trade timing", "",
          "| # | Dir | Open | Close | Duration (s) | Gap from previous close (s) |",
          "|---|---|---|---|---|---|"]
    for i, r in enumerate(rows, 1):
        o = r["open"].strftime("%H:%M:%S") if r["open"] else "?"
        md.append(f"| {i} | {r['dir']} | {o} | {r['close'].strftime('%H:%M:%S')} | "
                  f"{'' if r['dur'] is None else int(r['dur'])} | {'' if r['gap'] is None else int(r['gap'])} |")
    overlaps = [r for r in rows if r["gap"] is not None and r["gap"] < 0]
    ds, gs = stats([r["dur"] for r in rows]), stats([r["gap"] for r in rows])
    md += ["", f"- Durations: n={ds['n']}, min={ds['min']:.0f}s, median={ds['median']:.0f}s, "
               f"mean={ds['mean']:.1f}s, max={ds['max']:.0f}s",
           f"- Re-entry gaps: n={gs['n']}, min={gs['min']:.0f}s, median={gs['median']:.0f}s, "
           f"mean={gs['mean']:.1f}s, max={gs['max']:.0f}s",
           f"- Overlapping positions in sample: {len(overlaps)} (positions are strictly sequential here)",
           "- Direction after each close: " + ", ".join(
               f"{a['dir'][0]}->{b['dir'][0]}" for a, b in zip(rows, rows[1:])), ""]
    flips = sum(1 for a, b in zip(rows, rows[1:]) if a["dir"] != b["dir"])
    md.append(f"- Direction changes between consecutive trades: {flips} of {len(rows) - 1}")

    # 2. Pending order geometry
    bs, bs_sl, ss, ss_sl = 4043.95, 4042.95, 4041.88, 4042.88
    mid = (bs + ss) / 2
    md += ["", "## 2. Pending order geometry (single screenshot)", "",
           f"- Buy Stop {bs} SL {bs_sl} (SL distance {bs - bs_sl:.2f})",
           f"- Sell Stop {ss} SL {ss_sl} (SL distance {ss_sl - ss:.2f})",
           f"- Entry gap {bs - ss:.2f}; midpoint {mid:.3f}; each entry is {bs - mid:.3f} from the midpoint",
           f"- Buy SL sits {bs_sl - mid:+.3f} from midpoint, Sell SL {ss_sl - mid:+.3f}: both stops land within "
           f"0.04 of the midpoint, i.e. close to where price was when the bracket was armed.",
           "- If the bracket was placed around the then-current price with spread s, the offset from"
           " Ask (buy) / Bid (sell) was 1.035 - s/2:"]
    for s in (0.10, 0.20, 0.30, 0.40):
        md.append(f"  - spread {s:.2f} -> offset {1.035 - s / 2:.3f}")

    # 3. Price outcomes
    md += ["", "## 3. Price outcomes", "",
           "| Dir | Entry | Exit | Move ($) | Lots | Computed gross | Stated gross | Match |",
           "|---|---|---|---|---|---|---|---|"]
    wins = []
    with open(HERE / "evidence_prices.csv", newline="") as f:
        for r in csv.DictReader(f):
            e, x, v = float(r["entry"]), float(r["exit"]), float(r["volume"])
            move = (x - e) if r["direction"] == "Buy" else (e - x)
            g = round(move * v * CONTRACT, 2)
            if move > 0:
                wins.append(move)
            md.append(f"| {r['direction']} | {e} | {x} | {move:+.2f} | {v} | {g:+.2f} | "
                      f"{float(r['stated_gross_usd']):+.2f} | {'yes' if abs(g - float(r['stated_gross_usd'])) < 0.005 else 'NO'} |")
    avg_win = sum(wins) / len(wins)
    md.append(f"\n- Mean favourable move on the {len(wins)} winners: ${avg_win:.3f} per oz; loss sample: exactly $1.00 (= initial SL).")

    # 4. Order counts and commission
    filled, canceled, gross, comm = 2548, 1273, 7143.78, -3433.32
    cycles = filled / 2
    md += ["", "## 4. Order counts and commissions", "",
           f"- Filled {filled}, canceled {canceled}, total {filled + canceled}; filled/canceled = {filled / canceled:.4f}",
           f"- If each trade cycle = 1 entry fill + 1 exit fill (SL/close orders are listed as filled orders in MT5),",
           f"  cycles = {cycles:.0f}, which is within 1 of the canceled count ({canceled}).",
           "  This fits exactly ONE canceled order per trade: the unfilled side of a bracket.",
           "  It does not fit frequent cancel-and-replace repositioning (that would create many more cancels);",
           "  any following of price would then have to use order MODIFY, which creates no new tickets.",
           f"- Net {gross + comm:.2f}; commission = {abs(comm) / gross * 100:.1f}% of pre-commission profit",
           f"- Commission per cycle (if {cycles:.0f} cycles): ${abs(comm) / cycles:.3f}",
           f"- Pre-commission profit per cycle: ${gross / cycles:.3f}; net per cycle ${(gross + comm) / cycles:.3f}"]
    for c_rt in (3.0, 6.0, 7.0):
        md.append(f"  - implied average lots if round-turn commission is ${c_rt}/lot: {abs(comm) / cycles / c_rt:.3f}")
    md.append("  None of these equal 0.11-0.18, so either volumes grew over the period, the period includes other"
              " sizes, or the commission schedule differs from $3/lot. Needs the Deals export to settle.")

    # 5. Break-even win rate for the observed shape
    md += ["", "## 5. Break-even win rate for the observed trade shape", "",
           "Loss = SL distance + slippage + cost; win = average favourable exit - cost (all per oz).", "",
           "| Avg win ($) | SL ($) | Cost per RT ($/oz) | Break-even win rate |", "|---|---|---|---|"]
    for w in (0.30, avg_win, 0.50):
        for cost in (0.03, 0.06):
            p = (1.0 + cost) / ((w - cost) + (1.0 + cost))
            md.append(f"| {w:.2f} | 1.00 | {cost:.2f} | {p * 100:.1f}% |")
    md.append("\n$0.03/oz = $3/lot round turn; $0.06/oz = $6/lot round turn. Spread is paid separately via stop entry at Ask/Bid.")

    out = HERE / "evidence_analysis.md"
    out.write_text("\n".join(md) + "\n")
    print(out.read_text())


if __name__ == "__main__":
    main()
