"""Offline tick-level simulator of the OMNIX OCL bracket, for research only.

It replays real Bid/Ask ticks exported by MQL5/Scripts/OMNIX_OCL_ExportTicks.mq5 and models one
position at a time with a two-sided pending bracket, so entry and exit ideas can be screened quickly
before they are confirmed in the MT5 Strategy Tester (which remains the reference).

With --exact-fill 1, entry stops and SL exits fill at the order price (what the HexaFX accounts and the
Equiti demo actually showed: 0.00 slippage). run() also returns exit times (5th array) for hold-time stats.

Modelled:  stop (breakout) or limit (fade) brackets at +-offset, tighten-only follow with a step and a
minimum interval, pending lifetime, OCO cancel-on-fill, fixed SL, optional TP, optional trailing stop
(activation / distance / 0.05 step), optional max hold, spread cap, re-arm cooldown, optional trend
filter, round-turn commission. Stop orders and SL fill at the first tick that crosses them, at that
tick's price (so gaps cost slippage); limit orders and TP fill at their price.
Not modelled: execution latency, requotes/rejections, stop/freeze levels, news, the EA's risk gates.

Usage:
    python3 research/tick_sim.py --ticks DIR --grid default --split 2026-10-01
"""
import argparse
import gzip
import itertools
import sys
from pathlib import Path

import numpy as np

try:
    from numba import njit
except ImportError:  # pure-python fallback (slow)
    def njit(*a, **k):
        if a and callable(a[0]):
            return a[0]
        return lambda f: f


@njit(cache=True)
def simulate(t, bid, ask, mode, off, sl, tp, act, dist, follow_step, follow_min_ms, lifetime_ms,
             max_spread, comm, cooldown_ms, trend_ms, trend_min, max_hold_ms, be_trig, be_off, exact_fill,
             adx, adx_min, spk, spike_max):
    """Return (open_ms, dir, pnl, mfe, close_ms) arrays per closed trade. mode 0=breakout stops, 1=fade limits.
    adx: per-tick ADX of the last closed M5 bar (filter off when adx_min <= 0).
    spk: per-tick |mid change| over the spike window (filter off when spike_max <= 0).
    A failing filter cancels the bracket and blocks re-arming, like the EA withdrawing both sides."""
    n = t.shape[0]
    cap = n // 4 + 16
    o_t = np.empty(cap, np.int64)
    o_d = np.empty(cap, np.int8)
    o_p = np.empty(cap, np.float64)
    o_m = np.empty(cap, np.float64)
    o_x = np.empty(cap, np.int64)
    k = 0
    pos = 0
    entry = 0.0
    slp = 0.0
    tpp = 0.0
    open_t = 0
    mfe = 0.0
    placed = False
    up_px = 0.0   # upper order: buy stop (breakout) or sell limit (fade)
    dn_px = 0.0   # lower order: sell stop (breakout) or buy limit (fade)
    up_on = False
    dn_on = False
    placed_t = 0
    up_mod = 0
    dn_mod = 0
    cool_until = 0
    j = 0
    for i in range(n):
        ti = t[i]
        b = bid[i]
        a = ask[i]
        if i > 0 and ti - t[i - 1] > 60000:
            placed = False  # market gap (session break): pendings are re-armed afresh
        if pos != 0:
            # --- manage the open position
            if pos > 0:
                px = b
                fav = px - entry
            else:
                px = a
                fav = entry - px
            if fav > mfe:
                mfe = fav
            exit_px = 0.0
            done = False
            if (pos > 0 and px <= slp) or (pos < 0 and px >= slp):
                exit_px = slp if exact_fill else px
                done = True
            elif tp > 0 and ((pos > 0 and px >= tpp) or (pos < 0 and px <= tpp)):
                exit_px = tpp
                done = True
            elif max_hold_ms > 0 and ti - open_t >= max_hold_ms:
                exit_px = px
                done = True
            if done:
                o_t[k] = open_t
                o_d[k] = pos
                o_p[k] = (exit_px - entry) * pos - comm
                o_m[k] = mfe
                o_x[k] = ti
                k += 1
                pos = 0
                placed = False
                cool_until = ti + cooldown_ms
                continue
            if be_trig > 0 and fav >= be_trig:
                # break-even: lock entry + offset (+ commission) once the move reaches the trigger
                be = entry + (be_off + comm) * pos
                if (pos > 0 and be > slp) or (pos < 0 and be < slp):
                    slp = be
            if dist > 0 and fav >= act:
                if pos > 0:
                    nsl = px - dist
                    if nsl - slp >= 0.05:
                        slp = nsl
                else:
                    nsl = px + dist
                    if slp - nsl >= 0.05:
                        slp = nsl
            continue
        # --- flat
        if trend_ms > 0:
            while t[j] < ti - trend_ms:
                j += 1
            chg = (b + a) * 0.5 - (bid[j] + ask[j]) * 0.5
        else:
            chg = 0.0
        blocked = (adx_min > 0 and adx[i] < adx_min) or (spike_max > 0 and spk[i] > spike_max)
        if blocked:
            placed = False
            continue
        if placed:
            filled = 0
            fpx = 0.0
            if mode == 0:
                if up_on and a >= up_px:
                    filled = 1
                    fpx = up_px if exact_fill else a
                elif dn_on and b <= dn_px:
                    filled = -1
                    fpx = dn_px if exact_fill else b
            else:
                if up_on and b >= up_px:
                    filled = -1
                    fpx = up_px
                elif dn_on and a <= dn_px:
                    filled = 1
                    fpx = dn_px
            if filled != 0:
                pos = filled
                entry = fpx
                open_t = ti
                mfe = 0.0
                slp = entry - sl * pos
                tpp = entry + tp * pos
                placed = False
                continue
            if lifetime_ms > 0 and ti - placed_t >= lifetime_ms:
                placed = False
            else:
                # tighten-only follow toward the market
                if mode == 0:
                    want_up = a + off
                    want_dn = b - off
                else:
                    want_up = b + off
                    want_dn = a - off
                if up_on and up_px - want_up >= follow_step and ti - up_mod >= follow_min_ms:
                    up_px = want_up
                    up_mod = ti
                if dn_on and want_dn - dn_px >= follow_step and ti - dn_mod >= follow_min_ms:
                    dn_px = want_dn
                    dn_mod = ti
        if not placed and ti >= cool_until and a - b <= max_spread:
            allow_long = True
            allow_short = True
            if trend_min > 0:
                allow_long = chg >= trend_min
                allow_short = chg <= -trend_min
            if mode == 0:
                up_on = allow_long
                dn_on = allow_short
                up_px = a + off
                dn_px = b - off
            else:
                up_on = allow_short
                dn_on = allow_long
                up_px = b + off
                dn_px = a - off
            if up_on or dn_on:
                placed = True
                placed_t = ti
                up_mod = ti
                dn_mod = ti
    return o_t[:k], o_d[:k], o_p[:k], o_m[:k], o_x[:k]


DEFAULTS = dict(mode=0, off=0.95, sl=1.0, tp=0.0, act=0.30, dist=0.15, follow_step=0.10, follow_min_ms=1000,
                lifetime_ms=300000, max_spread=0.40, comm=0.03, cooldown_ms=0, trend_ms=0, trend_min=0.0,
                max_hold_ms=0, be_trig=0.0, be_off=0.0, exact_fill=0, adx_min=0.0, spike_ms=0, spike_max=0.0)


def adx_per_tick(t, b, a, bar_ms=300000, period=14):
    """Wilder ADX(period) on mid-price bars of bar_ms, mapped to each tick as the value of the last CLOSED bar
    (NaN -> 0 until enough bars)."""
    mid = (b + a) * 0.5
    bar = t // bar_ms
    starts = np.flatnonzero(np.r_[True, bar[1:] != bar[:-1]])
    ends = np.r_[starts[1:], len(t)] - 1
    hi = np.maximum.reduceat(mid, starts)
    lo = np.minimum.reduceat(mid, starts)
    cl = mid[ends]
    nb = len(starts)
    out_bar = np.zeros(nb)
    if nb > 2 * period + 1:
        up = hi[1:] - hi[:-1]
        dn = lo[:-1] - lo[1:]
        pdm = np.where((up > dn) & (up > 0), up, 0.0)
        mdm = np.where((dn > up) & (dn > 0), dn, 0.0)
        tr = np.maximum.reduce([hi[1:] - lo[1:], np.abs(hi[1:] - cl[:-1]), np.abs(lo[1:] - cl[:-1])])
        def wilder(x):
            r = np.empty_like(x)
            r[:period] = np.nan
            r[period - 1] = x[:period].sum()
            for k in range(period, len(x)):
                r[k] = r[k - 1] - r[k - 1] / period + x[k]
            return r
        atr, sp, sm = wilder(tr), wilder(pdm), wilder(mdm)
        with np.errstate(divide="ignore", invalid="ignore"):
            pdi = 100 * sp / atr
            mdi = 100 * sm / atr
            dx = 100 * np.abs(pdi - mdi) / (pdi + mdi)
        dx = np.nan_to_num(dx)
        adx = np.zeros_like(dx)
        first = 2 * period - 2
        adx[first] = dx[period - 1:first + 1].mean()
        for k in range(first + 1, len(dx)):
            adx[k] = (adx[k - 1] * (period - 1) + dx[k]) / period
        out_bar[1:] = adx          # adx for bar index 1..nb-1
    # tick in bar j sees the value of bar j-1 (last closed)
    bar_idx = np.searchsorted(starts, np.arange(len(t)), side="right") - 1
    prev = np.where(bar_idx > 0, out_bar[np.maximum(bar_idx - 1, 0)], 0.0)
    return prev.astype(np.float64)


def spike_per_tick(t, b, a, window_ms):
    mid = (b + a) * 0.5
    j = np.searchsorted(t, t - window_ms, side="left")
    return np.abs(mid - mid[j]).astype(np.float64)


_CACHE = {}


def _feature(name, t, b, a, arg):
    key = (name, id(t), len(t), arg)
    if key not in _CACHE:
        _CACHE[key] = adx_per_tick(t, b, a) if name == "adx" else spike_per_tick(t, b, a, arg)
    return _CACHE[key]


def load_ticks(paths):
    ts, bs, as_ = [], [], []
    for p in sorted(paths):
        opener = gzip.open if str(p).endswith(".gz") else open
        with opener(p, "rt") as f:
            arr = np.loadtxt(f, delimiter=",", skiprows=1, ndmin=2)
        if arr.size == 0:
            continue
        ts.append(arr[:, 0].astype(np.int64))
        bs.append(arr[:, 1])
        as_.append(arr[:, 2])
    t = np.concatenate(ts)
    b = np.concatenate(bs)
    a = np.concatenate(as_)
    order = np.argsort(t, kind="stable")
    t, b, a = t[order], b[order], a[order]
    ok = (b > 0) & (a >= b)
    return t[ok], b[ok], a[ok]


def stats(pnl):
    n = len(pnl)
    if n == 0:
        return dict(trades=0, net=0.0, pf=0.0, win=0.0, avg=0.0, dd=0.0)
    wins = pnl[pnl > 0].sum()
    loss = -pnl[pnl < 0].sum()
    eq = np.cumsum(pnl)
    dd = float((np.maximum.accumulate(np.concatenate([[0.0], eq]))[1:] - eq).max())
    return dict(trades=n, net=float(pnl.sum()), pf=float(wins / loss) if loss > 0 else float("inf"),
                win=float((pnl > 0).mean()), avg=float(pnl.mean()), dd=dd)


def run(t, b, a, **kw):
    p = dict(DEFAULTS)
    p.update(kw)
    f = lambda k: float(p[k])
    i = lambda k: int(p[k])
    return simulate(t, b, a, i("mode"), f("off"), f("sl"), f("tp"), f("act"), f("dist"), f("follow_step"),
                    i("follow_min_ms"), i("lifetime_ms"), f("max_spread"), f("comm"), i("cooldown_ms"),
                    i("trend_ms"), f("trend_min"), i("max_hold_ms"), f("be_trig"), f("be_off"), i("exact_fill"),
                    _feature("adx", t, b, a, 0) if f("adx_min") > 0 else np.zeros(1),
                    f("adx_min"),
                    _feature("spike", t, b, a, i("spike_ms")) if f("spike_max") > 0 else np.zeros(1),
                    f("spike_max"))


GRIDS = {
    # HexaFX-like structure seen in its history: fixed (not followed) +-1.0 bracket living ~20 s, ~21 s pause
    # after each close, SL 1.00, no TP, early break-even then a loose trail
    "hexa": dict(
        mode=[0],
        off=[0.8, 1.0, 1.2],
        sl=[1.0],
        follow=[False, True],
        lifetime_ms=[10000, 20000, 60000],
        cooldown_ms=[0, 20000],
        be=[(0.0, 0.0), (0.15, 0.01), (0.25, 0.01), (0.40, 0.02)],
        exit=[("trail", 0.30, 0.15), ("trail", 0.5, 0.3), ("trail", 0.8, 0.5)],
        trend=[(0, 0.0)],
    ),
    # filters on top of the live bracket: ADX(14, M5) floor like HexaFX's guide, and a spike block
    # (|mid change| over a short window) against entries filled on reversing spikes
    "filters": dict(
        mode=[0],
        off=[0.95, 1.0],
        sl=[1.0],
        follow=[True, False],
        lifetime_ms=[20000, 300000],
        cooldown_ms=[0],
        be=[(0.0, 0.0), (0.25, 0.01)],
        exit=[("trail", 0.30, 0.15), ("trail", 0.5, 0.3)],
        trend=[(0, 0.0)],
        adx=[0.0, 20.0, 25.0, 30.0],
        spike=[(0, 0.0), (1000, 0.5), (1000, 0.8), (3000, 1.0)],
    ),
    # owner's ask: no filters, tune only SL, break-even (covers commission; exits on the bid/ask so the
    # spread is included), trailing SL and the bracket distance
    "core": dict(
        mode=[0],
        off=[0.5, 0.7, 1.0, 1.5],
        sl=[0.3, 0.5, 0.7, 1.0],
        follow=[True, False],
        lifetime_ms=[20000, 300000],
        cooldown_ms=[0],
        be=[(0.15, 0.01), (0.25, 0.01), (0.40, 0.02)],
        exit=[("trail", 0.30, 0.15), ("trail", 0.5, 0.3), ("trail", 0.8, 0.4), ("trail", 1.2, 0.6)],
        trend=[(0, 0.0)],
    ),
    # finer search around the live prime-core pick (off 1.5 static 20 s, SL 0.3, BE 0.15, trail 0.30/0.15),
    # aimed at bigger average wins: wider bracket, later / wider trail, TP alternative
    "refine": dict(
        mode=[0],
        off=[1.25, 1.5, 2.0, 2.5],
        sl=[0.2, 0.3, 0.4],
        follow=[False],
        lifetime_ms=[10000, 20000, 40000],
        cooldown_ms=[0],
        be=[(0.10, 0.01), (0.15, 0.01), (0.20, 0.02)],
        exit=[("trail", 0.30, 0.15), ("trail", 0.40, 0.20), ("trail", 0.60, 0.25), ("trail", 0.80, 0.30),
              ("trail", 1.00, 0.40), ("tp", 0.8), ("tp", 1.5)],
        trend=[(0, 0.0)],
    ),
    "default": dict(
        mode=[0, 1],
        off=[0.5, 0.95, 1.5, 2.0, 3.0],
        sl=[0.5, 1.0, 2.0, 3.0],
        exit=[("trail", 0.30, 0.15), ("trail", 0.6, 0.3), ("trail", 1.0, 0.5),
              ("tp", 0.5), ("tp", 1.0), ("tp", 2.0)],
        trend=[(0, 0.0), (60000, 1.0), (300000, 2.0)],
    ),
}


def expand(grid):
    for mode, off, sl, ex, tr, fol, life, cool, be, adx, spk in itertools.product(
            grid["mode"], grid["off"], grid["sl"], grid["exit"], grid["trend"], grid.get("follow", [True]),
            grid.get("lifetime_ms", [300000]), grid.get("cooldown_ms", [0]), grid.get("be", [(0.0, 0.0)]),
            grid.get("adx", [0.0]), grid.get("spike", [(0, 0.0)])):
        kw = dict(mode=mode, off=off, sl=sl, trend_ms=tr[0], trend_min=tr[1],
                  follow_step=0.10 if fol else 1e9, lifetime_ms=life, cooldown_ms=cool, be_trig=be[0], be_off=be[1],
                  adx_min=adx, spike_ms=spk[0], spike_max=spk[1])
        if ex[0] == "trail":
            kw.update(tp=0.0, act=ex[1], dist=ex[2])
        else:
            kw.update(tp=ex[1], act=0.0, dist=0.0)
        yield kw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ticks", type=Path, required=True, help="folder with *.csv or *.csv.gz tick files")
    ap.add_argument("--glob", default="*.csv*")
    ap.add_argument("--grid", default="default")
    ap.add_argument("--split", default="2026-10-01", help="UTC date: before = in-sample, from = out-of-sample")
    ap.add_argument("--out", type=Path, default=Path("research/tick_sim_results.csv"))
    ap.add_argument("--comm", type=float, default=0.03, help="round-turn commission in price units per trade")
    ap.add_argument("--exact-fill", dest="exact_fill", type=int, default=0,
                    help="1: entry stops and SL exits fill exactly at the order price (0.00 slippage, as seen on the "
                         "HexaFX accounts and the Equiti demo); 0: at the first crossing tick")
    ap.add_argument("--spread", type=float, default=0.0,
                    help=">0: replace the feed's spread with this fixed value (ask = bid + spread), e.g. 0.09 to model "
                         "a raw/premium account; 0 = keep the feed's own Bid/Ask")
    a = ap.parse_args()
    t, b, ak = load_ticks(list(a.ticks.glob(a.glob)))
    if a.spread > 0:
        mid = (b + ak) / 2
        b, ak = mid - a.spread / 2, mid + a.spread / 2
    print(f"median spread {float(np.median(ak - b)):.3f}, commission {a.comm:.3f} per trade", file=sys.stderr)
    split_ms = int(np.datetime64(a.split, "ms").astype(np.int64))
    print(f"{len(t)} ticks {np.datetime64(int(t[0]), 'ms')} .. {np.datetime64(int(t[-1]), 'ms')}", file=sys.stderr)
    rows = []
    for kw in expand(GRIDS[a.grid]):
        kw["comm"] = a.comm
        kw["exact_fill"] = a.exact_fill
        ot, od, op, om, ox = run(t, b, ak, **kw)
        ins = stats(op[ot < split_ms])
        oos = stats(op[ot >= split_ms])
        rows.append((kw, ins, oos))
    keys = ["mode", "off", "sl", "tp", "act", "dist", "trend_ms", "trend_min", "follow_step", "lifetime_ms",
            "cooldown_ms", "be_trig", "be_off", "adx_min", "spike_ms", "spike_max"]
    with open(a.out, "w") as f:
        f.write(",".join(keys + [f"is_{s}" for s in ("trades", "net", "pf", "win", "avg", "dd")]
                         + [f"oos_{s}" for s in ("trades", "net", "pf", "win", "avg", "dd")]) + "\n")
        for kw, ins, oos in rows:
            f.write(",".join([str(kw[k]) for k in keys]
                             + [f"{ins[s]:.4f}" for s in ("trades", "net", "pf", "win", "avg", "dd")]
                             + [f"{oos[s]:.4f}" for s in ("trades", "net", "pf", "win", "avg", "dd")]) + "\n")
    print(f"wrote {a.out} ({len(rows)} configs)", file=sys.stderr)


if __name__ == "__main__":
    main()
