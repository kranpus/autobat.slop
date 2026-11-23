#!/usr/bin/env python3
"""Write scripts/core/ghost_scores.gd from balance-simulator results: each
unit's win rate at equal Strength, which training bands use to favour units
that fight well. Run the simulator with --all-units first (several runs
average out the noise):
    python3 tools/ghost_scores.py balance-results/balance_armies_*.csv
"""
import csv
import sys

acc = {}
for path in sys.argv[1:]:
    for r in csv.DictReader(open(path)):
        w, g = float(r["win_rate"]), int(r["games"])
        a = acc.setdefault(r["unit"], [0.0, 0])
        a[0] += w * g
        a[1] += g
if not acc:
    sys.exit("No CSV rows. Usage: python3 tools/ghost_scores.py <balance_armies_*.csv>...")
lines = [
    "class_name GhostScores",
    "extends RefCounted",
    "## Each unit's win rate at equal Strength in the balance simulator (written",
    "## by tools/ghost_scores.py from %d result file(s), %d games per unit on" % (len(sys.argv) - 1, round(sum(a[1] for a in acc.values()) / len(acc))),
    "## average). Training bands pick strong units more often, like a player would.",
    "## Units missing here count as 0.5.",
    "",
    "const WIN_RATE := {",
]
for u in sorted(acc):
    lines.append('\t"%s": %.3f,' % (u, acc[u][0] / acc[u][1]))
lines.append("}")
open("scripts/core/ghost_scores.gd", "w").write("\n".join(lines) + "\n")
print("wrote scripts/core/ghost_scores.gd (%d units)" % len(acc))
