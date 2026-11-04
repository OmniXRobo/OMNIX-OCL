"""Parser/logic test for research/reconstruct_lifecycle.py on a tiny SYNTHETIC history.
The fixture is hand-written to exercise the code paths; it is not market data."""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "research"))
import reconstruct_lifecycle as RL  # noqa: E402

OH = ["ticket", "symbol", "type", "state", "reason", "magic", "position_id", "position_by_id", "time_setup_msc",
      "time_done_msc", "time_expiration", "volume_initial", "volume_current", "price_open", "price_current", "sl",
      "tp", "type_filling", "type_time", "comment", "bid_at_setup", "ask_at_setup"]
DH = ["ticket", "order", "position_id", "symbol", "type", "entry", "reason", "magic", "time_msc", "volume", "price",
      "sl", "tp", "profit", "commission", "swap", "fee", "comment"]
T0 = 1_793_000_000_000


def o(tk, typ, state, reason, pid, setup, done, price, sl, bid=0, ask=0):
    return dict(zip(OH, [tk, "XAUUSD", typ, state, reason, 0, pid, 0, setup, done, 0, 0.11, 0, price, 0, sl, 0,
                         "ORDER_FILLING_RETURN", "ORDER_TIME_GTC", "synthetic", bid, ask]))


def d(tk, order, pid, typ, entry, reason, t, price, profit, comm):
    return dict(zip(DH, [tk, order, pid, "XAUUSD", typ, entry, reason, 0, t, 0.11, price, 0, 0, profit, comm, 0, 0, ""]))


def write(folder):
    orders = [
        # bracket 1: buy fills at +5s, sell canceled at fill (OCO); long closes by trailed SL in profit
        o(1, "ORDER_TYPE_BUY_STOP", "ORDER_STATE_FILLED", "ORDER_REASON_EXPERT", 1, T0, T0 + 5000, 4043.95, 4042.95, 4042.85, 4042.98),
        o(2, "ORDER_TYPE_SELL_STOP", "ORDER_STATE_CANCELED", "ORDER_REASON_EXPERT", 0, T0 + 10, T0 + 5300, 4041.88, 4042.88, 4042.85, 4042.98),
        o(3, "ORDER_TYPE_SELL", "ORDER_STATE_FILLED", "ORDER_REASON_SL", 1, T0 + 30000, T0 + 30000, 4044.23, 0),
        # bracket 2: sell fills, buy kept until close; short stopped at full SL
        o(4, "ORDER_TYPE_BUY_STOP", "ORDER_STATE_CANCELED", "ORDER_REASON_EXPERT", 0, T0 + 31000, T0 + 61500, 4045.00, 4044.00, 4043.90, 4044.03),
        o(5, "ORDER_TYPE_SELL_STOP", "ORDER_STATE_FILLED", "ORDER_REASON_EXPERT", 5, T0 + 31005, T0 + 40000, 4042.93, 4043.93, 4043.90, 4044.03),
        o(6, "ORDER_TYPE_BUY", "ORDER_STATE_FILLED", "ORDER_REASON_SL", 5, T0 + 61000, T0 + 61000, 4043.93, 0),
    ]
    deals = [
        d(11, 1, 1, "DEAL_TYPE_BUY", "DEAL_ENTRY_IN", "DEAL_REASON_EXPERT", T0 + 5000, 4043.95, 0, 0),
        d(12, 3, 1, "DEAL_TYPE_SELL", "DEAL_ENTRY_OUT", "DEAL_REASON_SL", T0 + 30000, 4044.23, 3.08, -0.33),
        d(13, 5, 5, "DEAL_TYPE_SELL", "DEAL_ENTRY_IN", "DEAL_REASON_EXPERT", T0 + 40000, 4042.93, 0, 0),
        d(14, 6, 5, "DEAL_TYPE_BUY", "DEAL_ENTRY_OUT", "DEAL_REASON_SL", T0 + 61000, 4043.93, -11.00, -0.33),
    ]
    for name, hdr, rows in (("history_orders.csv", OH, orders), ("history_deals.csv", DH, deals)):
        with open(folder / name, "w", newline="") as fh:
            w = csv.DictWriter(fh, hdr); w.writeheader(); w.writerows(rows)


def test_reconstruction(tmp_path):
    write(tmp_path)
    rep = RL.analyse(*RL.load(tmp_path))
    assert "brackets: 2" in rep
    assert "opposite canceled at fill (OCO): 1" in rep
    assert "opposite kept until position closed: 1" in rep
    assert "SL exits in profit (evidence of trailing/BE stops): 1" in rep
    assert "gross P/L -7.92, commission -0.66, net -8.58" in rep
    assert "commission per lot on exit deals: n=2, min=-3.000$" in rep
    # entry offset 0.97 from Ask/Bid for bracket 1
    assert "min=0.970$" in rep
