"""Every key in every preset must be a real input of the EA, with a value of the right shape."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "MQL5/Experts/OMNIX_OCL.mq5").read_text()
INPUTS = {name: typ for typ, name in re.findall(r"^input\s+(\w+)\s+(Inp\w+)\s*=", SRC, re.M)}


def test_inputs_parsed():
    assert len(INPUTS) > 80


def test_presets_match_inputs():
    for f in (ROOT / "MQL5/Presets").glob("*.set"):
        for line in f.read_text().splitlines():
            if not line.strip() or line.startswith(";"):
                continue
            k, v = line.split("=", 1)
            assert k in INPUTS, f"{f.name}: unknown input {k}"
            t = INPUTS[k]
            if t == "double":
                float(v)
            elif t in ("int", "long") or t.startswith("ENUM_"):
                int(v)
            elif t == "bool":
                assert v in ("true", "false"), f"{f.name}: {k}={v}"


def test_live_trading_disabled_at_compile_time():
    common = (ROOT / "MQL5/Include/OMNIX_OCL/Common.mqh").read_text()
    assert "#define OCL_LIVE_TRADING_ALLOWED false" in common
    assert "tm!=ACCOUNT_TRADE_MODE_DEMO && !OCL_LIVE_TRADING_ALLOWED" in SRC


def test_no_martingale_style_inputs():
    for word in ("martingale", "multiplier", "grid", "recovery"):
        assert not re.search(rf"^input[^\n]*{word}", SRC, re.I | re.M), word
