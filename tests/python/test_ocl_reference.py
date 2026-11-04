"""Checks the Python mirror of OCLMath.mqh against hand-derived vectors (tests/vectors.json)."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import ocl_reference as R  # noqa: E402

V = json.loads((Path(__file__).parents[1] / "vectors.json").read_text())
FN = {"round_to_tick": R.round_to_tick, "normalize_volume": R.normalize_volume,
      "money_per_price_per_lot": R.money_per_price_per_lot, "lots_for_risk": R.lots_for_risk,
      "min_stop_distance": R.min_stop_distance, "buy_stop_price": R.buy_stop_price,
      "sell_stop_price": R.sell_stop_price, "trail_candidate": R.trail_candidate,
      "break_even_candidate": R.break_even_candidate, "cost_as_price": R.cost_as_price,
      "nth_weekday": R.nth_weekday, "is_dst": R.is_dst, "server_offset_seconds": R.server_offset_seconds,
      "minute_of_day": R.minute_of_day, "in_window": R.in_window, "gold_name_score": R.gold_name_score}
CASES = [(name, row) for name, rows in V.items() for row in rows]


@pytest.mark.parametrize("name,row", CASES, ids=[f"{n}-{i}" for i, (n, _) in enumerate(CASES)])
def test_vector(name, row):
    *args, expected = row
    got = FN[name](*args)
    if isinstance(expected, float):
        assert got == pytest.approx(expected, abs=1e-6)
    else:
        assert got == expected


def test_observed_bracket_reproduces_with_013_spread():
    # Bid 4042.85 / Ask 4042.98 with 0.97 offset and 1.00 SL reproduces the screenshot bracket exactly.
    b = R.buy_stop_price(4042.98, 0.97, 0.0, 0.01)
    s = R.sell_stop_price(4042.85, 0.97, 0.0, 0.01)
    assert (round(b, 2), round(b - 1.0, 2)) == (4043.95, 4042.95)
    assert (round(s, 2), round(s + 1.0, 2)) == (4041.88, 4042.88)


def test_bracket_geometry_prevents_overlap():
    # With offset >= SL distance - spread, the long's SL is hit before the sell stop can fill.
    b = R.buy_stop_price(4042.98, 0.97, 0.0, 0.01)
    s = R.sell_stop_price(4042.85, 0.97, 0.0, 0.01)
    assert b - 1.0 > s
