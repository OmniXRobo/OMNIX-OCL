#!/usr/bin/env bash
# Offline checks that run without MetaTrader: Python mirror of the EA math, lifecycle tool, presets, MQL5 lint.
set -euo pipefail
cd "$(dirname "$0")"
python3 tests/gen_mql_vectors.py
python3 tests/lint_mql_format.py
python3 -m pytest -q tests/python
python3 research/analyze_evidence.py > /dev/null && echo "evidence analysis regenerated"
