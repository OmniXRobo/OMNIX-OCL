"""Static lint for MQL5 sources (no compiler available in CI):
 - StringFormat/PrintFormat placeholder count == argument count
 - balanced braces/parentheses per file
 - no '->' member access (MQL5 uses '.')
Exit code 1 on any finding."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "MQL5"
SPEC = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?(?:I64|ll|l|h)?[diouxXeEfgGcsS])")


def split_args(s):
    depth, cur, out, q = 0, "", [], False
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == '"' and (i == 0 or s[i - 1] != "\\"):
            q = not q
        if not q:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                out.append(cur); cur = ""; i += 1; continue
        cur += ch; i += 1
    out.append(cur)
    return out


def calls(text, name):
    for m in re.finditer(r"\b" + name + r"\s*\(", text):
        i, depth, q = m.end(), 1, False
        while i < len(text) and depth:
            ch = text[i]
            if ch == '"' and text[i - 1] != "\\":
                q = not q
            elif not q:
                depth += ch == "("
                depth -= ch == ")"
            i += 1
        yield text.count("\n", 0, m.start()) + 1, text[m.end():i - 1]


def strip_strings_comments(t):
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r'"(?:\\.|[^"\\])*"', '""', t)
    return t


bad = 0
for f in sorted(ROOT.rglob("*.mq*")):
    text = f.read_text().replace("\\\\", "__")
    for name in ("StringFormat", "PrintFormat"):
        for line, body in calls(text, name):
            args = split_args(body)
            fmt = args[0].strip()
            lits = re.findall(r'"((?:\\.|[^"\\])*)"', fmt)
            if not lits:
                continue
            n = sum(1 for x in SPEC.findall("".join(lits)) if x != "%%")
            if n != len(args) - 1:
                print(f"{f.relative_to(ROOT)}:{line}: {name} has {n} placeholders but {len(args) - 1} args"); bad += 1
    code = strip_strings_comments(text)
    for a, b in ("()", "{}", "[]"):
        if code.count(a) != code.count(b):
            print(f"{f.relative_to(ROOT)}: unbalanced {a}{b} {code.count(a)} vs {code.count(b)}"); bad += 1
    if "->" in code:
        print(f"{f.relative_to(ROOT)}: '->' found; MQL5 uses '.' for pointers"); bad += 1
print("lint findings:", bad)
sys.exit(1 if bad else 0)
