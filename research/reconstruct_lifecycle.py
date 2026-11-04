"""
OMNIX OCL - order lifecycle reconstruction (Milestone 1 tooling).

Input: the two CSV files written by MQL5/Scripts/OMNIX_OCL_ExportHistory.mq5
       (history_orders.csv, history_deals.csv)
Output: a markdown report answering the Section 3-5 research questions.

    python3 research/reconstruct_lifecycle.py <folder_with_csvs> [--out report.md]

What MT5 history can and cannot tell us:
  * It records each order's FINAL price/SL and its setup and done times.
  * It does NOT record intermediate modifications (pending price moves, SL trails).
    Those are only visible in the terminal journal or in OMNIX OCL's own event log.
  * Exit orders triggered by SL appear as filled market orders with reason SL.
"""
from __future__ import annotations

import argparse
import csv
import statistics as st
from collections import Counter, defaultdict
from pathlib import Path

PENDING = {"ORDER_TYPE_BUY_STOP", "ORDER_TYPE_SELL_STOP", "ORDER_TYPE_BUY_LIMIT", "ORDER_TYPE_SELL_LIMIT",
           "ORDER_TYPE_BUY_STOP_LIMIT", "ORDER_TYPE_SELL_STOP_LIMIT"}
BRACKET_WINDOW_MS = 1500   # two opposite pendings set up within this window = one bracket
NEAR_MS = 2000             # "immediately" threshold for cancel-after-fill / cancel-after-close


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def load(folder: Path):
    with open(folder / "history_orders.csv", newline="", encoding="utf-8-sig") as fh:
        orders = list(csv.DictReader(fh))
    with open(folder / "history_deals.csv", newline="", encoding="utf-8-sig") as fh:
        deals = list(csv.DictReader(fh))
    for o in orders:
        o["setup"] = int(o["time_setup_msc"]); o["done"] = int(o["time_done_msc"] or 0)
        o["price"] = f(o["price_open"]); o["sl_f"] = f(o["sl"])
        o["bid"] = f(o.get("bid_at_setup")); o["ask"] = f(o.get("ask_at_setup"))
    for d in deals:
        d["t"] = int(d["time_msc"])
        for k in ("volume", "price", "sl", "profit", "commission", "swap", "fee"):
            d[k] = f(d.get(k))
    return orders, deals


def q(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def summ(xs, unit=""):
    xs = [x for x in xs if x == x]
    if not xs:
        return "no data"
    return (f"n={len(xs)}, min={min(xs):.3f}{unit}, p25={q(xs, .25):.3f}{unit}, median={q(xs, .5):.3f}{unit}, "
            f"p75={q(xs, .75):.3f}{unit}, max={max(xs):.3f}{unit}")


def positions_from_deals(deals):
    pos = defaultdict(lambda: {"in": [], "out": []})
    for d in deals:
        if d["type"] not in ("DEAL_TYPE_BUY", "DEAL_TYPE_SELL"):
            continue
        pid = d["position_id"]
        if d["entry"] == "DEAL_ENTRY_IN":
            pos[pid]["in"].append(d)
        elif d["entry"] in ("DEAL_ENTRY_OUT", "DEAL_ENTRY_OUT_BY", "DEAL_ENTRY_INOUT"):
            pos[pid]["out"].append(d)
    out = {}
    for pid, p in pos.items():
        if not p["in"]:
            continue
        i0 = min(p["in"], key=lambda d: d["t"])
        rec = {"id": pid, "dir": 1 if i0["type"] == "DEAL_TYPE_BUY" else -1, "open_t": i0["t"],
               "entry": i0["price"], "vol": sum(d["volume"] for d in p["in"]), "in_order": i0["order"],
               "comm_in": sum(d["commission"] for d in p["in"])}
        if p["out"]:
            o1 = max(p["out"], key=lambda d: d["t"])
            rec.update(close_t=o1["t"], exit=o1["price"], reason=o1["reason"],
                       profit=sum(d["profit"] for d in p["out"]),
                       comm_out=sum(d["commission"] for d in p["out"]),
                       swap=sum(d["swap"] for d in p["out"]), fee=sum(d["fee"] for d in p["out"] + p["in"]))
        out[pid] = rec
    return out


def analyse(orders, deals):
    md = ["# Order lifecycle reconstruction", ""]
    by_state = Counter((o["type"], o["state"]) for o in orders)
    states = Counter(o["state"] for o in orders)
    md += ["## Order totals", "", "| Type | State | Count |", "|---|---|---|"]
    md += [f"| {t} | {s} | {n} |" for (t, s), n in sorted(by_state.items())]
    filled = states.get("ORDER_STATE_FILLED", 0)
    canceled = states.get("ORDER_STATE_CANCELED", 0) + states.get("ORDER_STATE_EXPIRED", 0)
    md += ["", f"Filled {filled}, canceled/expired {canceled}, ratio {filled / max(canceled, 1):.3f}"]
    reasons = Counter(o["reason"] for o in orders if o["state"] == "ORDER_STATE_FILLED" and o["type"] not in PENDING)
    md += ["", "Filled non-pending orders by reason (exit orders show as ORDER_REASON_SL / _EXPERT / _CLIENT):", ""]
    md += [f"- {r}: {n}" for r, n in reasons.most_common()]

    pend = [o for o in orders if o["type"] in PENDING]
    life_f = [(o["done"] - o["setup"]) / 1000 for o in pend if o["state"] == "ORDER_STATE_FILLED" and o["done"]]
    life_c = [(o["done"] - o["setup"]) / 1000 for o in pend if o["state"] != "ORDER_STATE_FILLED" and o["done"]]
    md += ["", "## Pending order lifespan (seconds)", "", f"- until fill: {summ(life_f, 's')}",
           f"- until cancel/expiry: {summ(life_c, 's')}"]

    dist = []
    for o in pend:
        if o["ask"] > 0 and o["type"] == "ORDER_TYPE_BUY_STOP":
            dist.append((o["price"] - o["ask"], o["ask"] - o["bid"]))
        elif o["bid"] > 0 and o["type"] == "ORDER_TYPE_SELL_STOP":
            dist.append((o["bid"] - o["price"], o["ask"] - o["bid"]))
    sl_d = [abs(o["price"] - o["sl_f"]) for o in pend if o["sl_f"] > 0]
    md += ["", "## Placement geometry (FINAL order price vs market at setup; modifications are invisible here)", "",
           f"- entry offset from Ask(buy)/Bid(sell): {summ([d for d, _ in dist], '$')}",
           f"- spread at setup: {summ([s for _, s in dist], '$')}",
           f"- SL distance on pending orders: {summ(sl_d, '$')}",
           "- If final offsets are much larger than offsets implied at setup, orders were modified after placement."]

    # brackets
    pend.sort(key=lambda o: o["setup"])
    brackets, used = [], set()
    for i, a in enumerate(pend):
        if a["ticket"] in used:
            continue
        for b in pend[i + 1:]:
            if b["setup"] - a["setup"] > BRACKET_WINDOW_MS:
                break
            if b["ticket"] not in used and ("BUY" in a["type"]) != ("BUY" in b["type"]):
                brackets.append((a, b)); used.update({a["ticket"], b["ticket"]}); break
    singles = len(pend) - 2 * len(brackets)
    md += ["", "## Brackets (Buy Stop + Sell Stop set up together)", "",
           f"- brackets: {len(brackets)}; pending orders not part of a bracket: {singles}"]

    pos = positions_from_deals(deals)
    pos_by_order = {p["in_order"]: p for p in pos.values()}
    policy = Counter()
    lag_fill, lag_close = [], []
    for a, b in brackets:
        fills = [o for o in (a, b) if o["state"] == "ORDER_STATE_FILLED"]
        if len(fills) == 2:
            p1, p2 = sorted(fills, key=lambda o: o["done"])
            p = pos_by_order.get(p1["ticket"])
            if p and p.get("close_t") and p2["done"] < p["close_t"]:
                policy["both filled, overlapping positions"] += 1
            else:
                policy["both filled, second after first closed (opposite kept)"] += 1
            continue
        if len(fills) == 0:
            policy["neither filled (both canceled/expired)"] += 1
            continue
        fo = fills[0]; other = b if fo is a else a
        p = pos_by_order.get(fo["ticket"])
        if not p:
            policy["filled but no matching position deals"] += 1
            continue
        dfill = (other["done"] - p["open_t"]) / 1000
        lag_fill.append(dfill)
        if p.get("close_t"):
            lag_close.append((other["done"] - p["close_t"]) / 1000)
        if abs(dfill) * 1000 <= NEAR_MS:
            policy["opposite canceled at fill (OCO)"] += 1
        elif p.get("close_t") and abs(other["done"] - p["close_t"]) <= NEAR_MS:
            policy["opposite kept until position closed"] += 1
        elif p.get("close_t") and other["done"] > p["close_t"]:
            policy["opposite outlived the position"] += 1
        else:
            policy["opposite canceled while position open (other rule)"] += 1
    md += ["", "### What happens to the opposite order", ""] + [f"- {k}: {v}" for k, v in policy.most_common()]
    md += [f"- opposite cancel time minus fill time: {summ(lag_fill, 's')}",
           f"- opposite cancel time minus position close: {summ(lag_close, 's')}"]

    # positions
    closed = sorted((p for p in pos.values() if p.get("close_t")), key=lambda p: p["open_t"])
    md += ["", "## Positions", ""]
    if closed:
        dur = [(p["close_t"] - p["open_t"]) / 1000 for p in closed]
        gaps = [(b["open_t"] - a["close_t"]) / 1000 for a, b in zip(closed, closed[1:])]
        overl = sum(1 for g in gaps if g < 0)
        moves = [(p["exit"] - p["entry"]) * p["dir"] for p in closed]
        net = [p["profit"] + p["comm_in"] + p["comm_out"] + p["swap"] + p["fee"] for p in closed]
        gross = sum(p["profit"] for p in closed)
        comm = sum(p["comm_in"] + p["comm_out"] for p in closed)
        wins = [n for n in net if n > 0]; losses = [n for n in net if n <= 0]
        md += [f"- closed positions: {len(closed)}; overlapping with previous: {overl}",
               f"- duration: {summ(dur, 's')}", f"- re-entry gap (close to next open): {summ(gaps, 's')}",
               f"- price move captured: {summ(moves, '$')}",
               f"- exit reasons: {dict(Counter(p['reason'] for p in closed))}",
               f"- SL exits in profit (evidence of trailing/BE stops): "
               f"{sum(1 for p, m in zip(closed, moves) if p['reason'] == 'DEAL_REASON_SL' and m > 0)}",
               f"- gross P/L {gross:.2f}, commission {comm:.2f}, net {sum(net):.2f}",
               f"- net win rate {len(wins) / len(net) * 100:.1f}%, avg win {st.mean(wins) if wins else 0:.2f}, "
               f"avg loss {st.mean(losses) if losses else 0:.2f}",
               f"- profit factor (net) {sum(wins) / abs(sum(losses)) if losses and sum(losses) else float('inf'):.3f}"]
        cin = [p["comm_in"] / p["vol"] for p in closed if p["vol"]]
        cout = [p["comm_out"] / p["vol"] for p in closed if p["vol"]]
        md += ["", "### Commission interpretation", "",
               f"- commission per lot on entry deals: {summ(cin, '$')}",
               f"- commission per lot on exit deals: {summ(cout, '$')}",
               "- If entry is 0 and exit is -3.00, the schedule is $3/lot charged once at close (round turn $3).",
               f"- volumes used: {dict(Counter(round(p['vol'], 2) for p in closed).most_common(10))}"]
    return "\n".join(md) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    rep = analyse(*load(a.folder))
    if a.out:
        a.out.write_text(rep)
    print(rep)


if __name__ == "__main__":
    main()
