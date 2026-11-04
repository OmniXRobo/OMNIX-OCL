"""Summarise MT5 optimisation result exports (File > Export to XML, 'XML Spreadsheet 2003' format).

    python3 backtests/parse_tester_report.py OMNIX_OCL_s1_exit.xml [OMNIX_OCL_s1_exit.forward.xml]

Prints every pass sorted by the custom criterion ('Result'), with profit, PF, trades and drawdown.
If a forward file is given, back and forward results are shown side by side by pass number,
so a configuration that only wins in-sample is visible at once.
"""
import sys
import xml.etree.ElementTree as ET

NS = {"ss": "urn:schemas-microsoft-com:office:spreadsheet"}


def rows(path):
    root = ET.parse(path).getroot()
    out = []
    for row in root.iter("{urn:schemas-microsoft-com:office:spreadsheet}Row"):
        cells = [(d.text or "") for d in row.iter("{urn:schemas-microsoft-com:office:spreadsheet}Data")]
        out.append(cells)
    head, body = out[0], out[1:]
    return [dict(zip(head, r)) for r in body if r]


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return float("nan")


def main():
    back = rows(sys.argv[1])
    fwd = {r.get("Pass"): r for r in rows(sys.argv[2])} if len(sys.argv) > 2 else {}
    params = [k for k in back[0] if k.startswith("Inp")]
    back.sort(key=lambda r: num(r.get("Result")), reverse=True)
    hdr = ["Pass"] + params + ["Result", "Profit", "Profit Factor", "Trades", "Equity DD %"]
    if fwd:
        hdr += ["FWD Result", "FWD Profit", "FWD PF", "FWD Trades"]
    print(" | ".join(hdr))
    for r in back:
        line = [r.get("Pass", "")] + [r.get(p, "") for p in params] + [
            r.get("Result", ""), r.get("Profit", ""), r.get("Profit Factor", ""), r.get("Trades", ""),
            r.get("Equity DD %", "")]
        if fwd:
            f = fwd.get(r.get("Pass"), {})
            line += [f.get("Result", ""), f.get("Profit", ""), f.get("Profit Factor", ""), f.get("Trades", "")]
        print(" | ".join(line))


if __name__ == "__main__":
    main()
