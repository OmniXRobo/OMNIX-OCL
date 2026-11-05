import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "research"))
import tick_sim as ts  # noqa: E402


def ticks(mids, spread=0.10, step_ms=500):
    m = np.array(mids, float)
    t = np.arange(len(m), dtype=np.int64) * step_ms
    return t, m - spread / 2, m + spread / 2


def test_breakout_long_hits_sl():
    # bracket at mid 100 (ask 100.05 -> buy stop 101.00), price rises to fill then falls to SL
    t, b, a = ticks([100, 100.5, 101.0, 100.5, 100.0, 99.9, 99.9])
    ot, od, op, om, ox = ts.run(t, b, a, off=0.95, sl=1.0, act=5, dist=0.15, comm=0.0)
    assert list(od) == [1]
    assert op[0] <= -1.0 + 1e-9


def test_fade_short_takes_profit():
    # sell limit at bid+0.95 (100.90); price spikes to 101.0 then returns down 1.0
    t, b, a = ticks([100, 100.5, 101.0, 100.5, 99.8, 99.8])
    ot, od, op, om, ox = ts.run(t, b, a, mode=1, off=0.95, sl=1.0, tp=1.0, dist=0.0, comm=0.0)
    assert list(od) == [-1]
    assert abs(op[0] - 1.0) < 1e-9


def test_trailing_locks_profit():
    t, b, a = ticks([100, 101.0, 101.5, 102.0, 101.9, 101.8, 101.7, 101.7])
    ot, od, op, om, ox = ts.run(t, b, a, off=0.95, sl=1.0, act=0.3, dist=0.15, comm=0.0)
    assert od[0] == 1 and op[0] > 0


def test_break_even_scratches_loser():
    # long fills at 101.05, rises 0.3 (BE trigger 0.25), then falls through entry: exits near entry, not at -1
    t, b, a = ticks([100, 101.0, 101.4, 101.3, 101.2, 101.1, 101.0, 100.5, 100.0])
    ot, od, op, om, ox = ts.run(t, b, a, off=0.95, sl=1.0, act=5, dist=0.15, be_trig=0.25, be_off=0.01, comm=0.0)
    assert od[0] == 1 and -0.2 < op[0] < 0.05


def test_exact_fill_uses_order_prices():
    t, b, a = ticks([100, 101.3, 100.0, 99.5])
    _, od, op, _, _ = ts.run(t, b, a, off=0.95, sl=1.0, act=5, dist=0.15, comm=0.0, exact_fill=1)
    assert od[0] == 1 and abs(op[0] + 1.0) < 1e-9


def test_spike_filter_blocks_spike_entry():
    # a 1.0 jump inside one second fills the buy stop without the filter, and is skipped with it
    t, b, a = ticks([100, 100, 101.2, 100.0, 99.5, 99.5], step_ms=400)
    _, od, _, _, _ = ts.run(t, b, a, off=0.95, sl=1.0, act=5, dist=0.15, comm=0.0)
    assert list(od) == [1]
    _, od2, _, _, _ = ts.run(t, b, a, off=0.95, sl=1.0, act=5, dist=0.15, comm=0.0, spike_ms=1000, spike_max=0.5)
    assert len(od2) == 0


def test_adx_high_in_trend_low_in_range():
    n_bars, per_bar = 80, 10
    step = 300000 // per_bar
    trend = np.repeat(np.arange(n_bars) * 1.0, per_bar) + np.tile(np.linspace(0, 0.5, per_bar), n_bars)
    chop = 100 + np.tile(np.r_[np.linspace(0, 1, per_bar // 2), np.linspace(1, 0, per_bar // 2)], n_bars)
    for mids, want_high in ((trend, True), (chop, False)):
        t, b, a = ticks(mids, step_ms=step)
        adx = ts.adx_per_tick(t, b, a)
        assert len(adx) == len(t)
        assert (adx[-1] > 40) == want_high
