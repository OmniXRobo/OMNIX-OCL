"""Generate MT5 Strategy Tester configs for the structural comparisons in backtests/TEST_PLAN.md.

    python3 backtests/make_tester_configs.py --symbol XAUUSD.sd --from 2026.05.01 --to 2026.10.31 \
        --preset MQL5/Presets/Equiti.set --out backtests/configs

For each stage it writes <stage>.ini (copy to the terminal data folder) and <stage>.set
(copy to <data>\\MQL5\\Profiles\\Tester\\). Run:  terminal64.exe /config:"<data>\\<stage>.ini"
Every stage uses real ticks, slow complete optimisation, custom criterion (OnTester) and a
1/3 forward (out-of-sample) segment, so the in-sample winner is checked on unseen data.
"""
import argparse
from pathlib import Path

STAGES = {
    "s1_exit":    {"InpExitProfile": (1, 1, 6)},
    "s2_oco":     {"InpOcoMode": (0, 1, 2)},
    "s3_rearm":   {"InpRearmMode": (0, 1, 4)},
    "s4_pending": {"InpPendingMode": (0, 1, 2)},
    "s5_dist":    {"InpDistMode": (0, 1, 3)},
}


def load_preset(path):
    vals = {}
    for line in Path(path).read_text().splitlines():
        if line.strip() and not line.startswith(";") and "=" in line:
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", required=True)
    ap.add_argument("--from", dest="date_from", required=True)
    ap.add_argument("--to", dest="date_to", required=True)
    ap.add_argument("--preset", default="MQL5/Presets/Equiti.set")
    ap.add_argument("--deposit", type=int, default=10000)
    ap.add_argument("--leverage", type=int, default=100)
    ap.add_argument("--out", type=Path, default=Path("backtests/configs"))
    a = ap.parse_args()
    base = load_preset(a.preset)
    a.out.mkdir(parents=True, exist_ok=True)
    for stage, opt in STAGES.items():
        lines = []
        for k, v in base.items():
            if k in opt:
                start, step, stop = opt[k]
                lines.append(f"{k}={v}||{start}||{step}||{stop}||Y")
            else:
                lines.append(f"{k}={v}")
        lines.append(f"InpStrategyTag={stage}")
        (a.out / f"{stage}.set").write_text("\r\n".join(lines) + "\r\n")
        ini = f"""[Tester]
Expert=OMNIX_OCL.ex5
ExpertParameters={stage}.set
Symbol={a.symbol}
Period=M1
Model=4
Optimization=1
OptimizationCriterion=6
FromDate={a.date_from}
ToDate={a.date_to}
ForwardMode=2
Deposit={a.deposit}
Currency=USD
Leverage={a.leverage}
ExecutionMode=-1
Report=OMNIX_OCL_{stage}
ReplaceReport=1
ShutdownTerminal=1
Visual=0
"""
        (a.out / f"{stage}.ini").write_text(ini.replace("\n", "\r\n"))
    print("wrote", len(STAGES), "stages to", a.out)


if __name__ == "__main__":
    main()
