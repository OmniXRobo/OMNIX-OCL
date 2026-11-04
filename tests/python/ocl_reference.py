"""Python mirror of MQL5/Include/OMNIX_OCL/OCLMath.mqh.

Kept line-for-line equivalent so the same test vectors can check both
implementations: pytest checks this file here, and the MQL5 script
OMNIX_OCL_UnitTests.mq5 checks the .mqh on the VPS with the generated vectors.
"""
from __future__ import annotations

import calendar
import math
from datetime import datetime, timezone

EPS = 1e-9


def mql_round(x: float) -> float:
    # MQL5 MathRound rounds half away from zero
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def round_to_tick(price, tick):
    if tick <= 0:
        return price
    return mql_round(price / tick) * tick


def normalize_volume(volume, vmin, vmax, vstep):
    if vstep <= 0 or volume < vmin - EPS:
        return 0.0
    v = math.floor((volume + EPS) / vstep) * vstep
    if v > vmax:
        v = math.floor((vmax + EPS) / vstep) * vstep
    if v < vmin - EPS:
        return 0.0
    return round(v, 8)


def money_per_price_per_lot(tick_value, tick_size):
    return 0.0 if tick_size <= 0 else tick_value / tick_size


def lots_for_risk(risk_money, stop_dist, mpl, cost_per_lot, vmin, vmax, vstep):
    if risk_money <= 0 or stop_dist <= 0 or mpl <= 0:
        return 0.0
    return normalize_volume(risk_money / (stop_dist * mpl + max(cost_per_lot, 0.0)), vmin, vmax, vstep)


def min_stop_distance(stops_pts, freeze_pts, point, buffer):
    return max(stops_pts, freeze_pts) * point + max(buffer, 0.0)


def buy_stop_price(ask, offset, min_dist, tick):
    p = round_to_tick(ask + max(offset, min_dist), tick)
    if p - ask < min_dist - EPS:
        p = round_to_tick(p + tick, tick)
    return p


def sell_stop_price(bid, offset, min_dist, tick):
    p = round_to_tick(bid - max(offset, min_dist), tick)
    if bid - p < min_dist - EPS:
        p = round_to_tick(p - tick, tick)
    return p


def trail_candidate(d, entry, bid, ask, cur_sl, activation, trail, step, min_dist, tick):
    if trail <= 0:
        return 0.0
    if d > 0:
        if bid - entry < activation - EPS:
            return 0.0
        sl = round_to_tick(bid - max(trail, min_dist), tick)
        if bid - sl < min_dist - EPS:
            sl = round_to_tick(sl - tick, tick)
        if cur_sl > 0 and sl < cur_sl + step - EPS:
            return 0.0
        return sl
    if entry - ask < activation - EPS:
        return 0.0
    s = round_to_tick(ask + max(trail, min_dist), tick)
    if s - ask < min_dist - EPS:
        s = round_to_tick(s + tick, tick)
    if cur_sl > 0 and s > cur_sl - step + EPS:
        return 0.0
    return s


def break_even_candidate(d, entry, bid, ask, cur_sl, trigger, offset, cost_price, min_dist, tick):
    if d > 0:
        if bid - entry < trigger - EPS:
            return 0.0
        sl = round_to_tick(entry + cost_price + offset, tick)
        if bid - sl < min_dist - EPS:
            return 0.0
        if cur_sl > 0 and cur_sl >= sl - EPS:
            return 0.0
        return sl
    if entry - ask < trigger - EPS:
        return 0.0
    s = round_to_tick(entry - cost_price - offset, tick)
    if s - ask < min_dist - EPS:
        return 0.0
    if cur_sl > 0 and cur_sl <= s + EPS:
        return 0.0
    return s


def cost_as_price(comm_rt_per_lot, mpl):
    return 0.0 if mpl <= 0 else comm_rt_per_lot / mpl


def nth_weekday(year, month, weekday_sun0, n):
    # weekday_sun0: 0=Sunday like MQL5
    first_dow = (datetime(year, month, 1).weekday() + 1) % 7
    day = 1 + ((weekday_sun0 - first_dow + 7) % 7)
    if n > 0:
        return day + 7 * (n - 1)
    dim = calendar.monthrange(year, month)[1]
    while day + 7 <= dim:
        day += 7
    return day


def is_dst(utc_ts: int, rule: int) -> bool:
    if rule == 0:
        return False
    y = datetime.fromtimestamp(utc_ts, tz=timezone.utc).year
    if rule == 1:
        s = datetime(y, 3, nth_weekday(y, 3, 0, 2), 7, tzinfo=timezone.utc)
        e = datetime(y, 11, nth_weekday(y, 11, 0, 1), 6, tzinfo=timezone.utc)
    else:
        s = datetime(y, 3, nth_weekday(y, 3, 0, -1), 1, tzinfo=timezone.utc)
        e = datetime(y, 10, nth_weekday(y, 10, 0, -1), 1, tzinfo=timezone.utc)
    return s.timestamp() <= utc_ts < e.timestamp()


def server_offset_seconds(utc_ts, base_hours, rule):
    return (base_hours + (1 if is_dst(utc_ts, rule) else 0)) * 3600


def minute_of_day(utc_ts, zone_offset):
    d = datetime.fromtimestamp(utc_ts + zone_offset, tz=timezone.utc)
    return d.hour * 60 + d.minute


def in_window(minute, start, end):
    if start == end:
        return True
    if start < end:
        return start <= minute < end
    return minute >= start or minute < end


def gold_name_score(name: str) -> int:
    n = name.upper()
    if n.startswith("XAUUSD"):
        return 100 if len(n) == 6 else 90
    if n.find("XAUUSD") > 0:
        return 70
    if n == "GOLD":
        return 80
    if n.startswith("GOLD") and not any(x in n for x in ("EUR", "AUD", "GBP", "JPY", "CHF", "FUT")):
        return 60
    return 0
