#!/bin/bash
# Renders harness/history.jsonl into harness/dashboard.html — a static page in
# Lokt's design language. Run any time: ./harness/dashboard.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, html
from datetime import datetime, timezone
from pathlib import Path

runs = []
p = Path("harness/history.jsonl")
if p.exists():
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            runs.append(json.loads(line))
        except json.JSONDecodeError:
            pass  # never let one bad line kill the dashboard
runs.sort(key=lambda r: r.get("ts", ""))

def latest(kind):
    for r in reversed(runs):
        if r.get("kind") == kind:
            return r
    return None

def ago(ts):
    try:
        dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        s = (datetime.now(timezone.utc) - dt).total_seconds()
        if s < 90: return "just now"
        if s < 5400: return f"{int(s//60)} min ago"
        if s < 129600: return f"{int(s//3600)} h ago"
        return f"{int(s//86400)} d ago"
    except Exception:
        return ts

# streak = consecutive passing checks runs, newest backwards
streak = 0
for r in reversed([r for r in runs if r.get("kind") == "checks"]):
    if r.get("pass"): streak += 1
    else: break

m1b_series = [(r["ts"], r["m1b"]) for r in runs if r.get("kind") == "checks" and "m1b" in r]
m1b_now = m1b_series[-1][1] if m1b_series else None

GOOD, BAD, VOLT = "#3FE08A", "#FF5C5C", "#D6FF3F"
INK, INK2, INK3 = "#F4F4F5", "#9A9AA2", "#5E5E66"
BG, CARD, LINE = "#0B0B0C", "#141416", "#26262A"

def tile(label, run):
    if run is None:
        return f'<div class="tile"><div class="micro">{label}</div><div class="val" style="color:{INK3}">—</div><div class="sub">no runs yet</div></div>'
    ok = run.get("pass")
    color, glyph, word = (GOOD, "✓", "PASS") if ok else (BAD, "✕", "FAIL")
    return (f'<div class="tile"><div class="micro">{label}</div>'
            f'<div class="val" style="color:{color}">{glyph} {word}</div>'
            f'<div class="sub">{ago(run["ts"])}</div></div>')

# Sparkline: single series → dim line, latest point volt, per-point <title> hover.
def sparkline():
    if len(m1b_series) < 2:
        return f'<div class="sub">Trend appears after a few more runs (each commit adds one).</div>'
    W, H, PAD = 620, 96, 8
    vals = [v for _, v in m1b_series][-40:]
    tss  = [t for t, _ in m1b_series][-40:]
    lo, hi = min(vals), max(vals)
    span = max(hi - lo, 1)
    n = len(vals)
    def xy(i, v):
        x = PAD + i * (W - 2*PAD) / max(n - 1, 1)
        y = PAD + (hi - v) * (H - 2*PAD) / span
        return x, y
    pts = " ".join(f"{xy(i,v)[0]:.1f},{xy(i,v)[1]:.1f}" for i, v in enumerate(vals))
    lx, ly = xy(n - 1, vals[-1])
    dots = "".join(
        f'<circle cx="{xy(i,v)[0]:.1f}" cy="{xy(i,v)[1]:.1f}" r="7" fill="transparent">'
        f'<title>{html.escape(tss[i])} — {v} direct accesses</title></circle>'
        for i, v in enumerate(vals))
    return (f'<svg viewBox="0 0 {W} {H}" width="100%" height="{H}" role="img" '
            f'aria-label="M1b direct-access count over recent runs">'
            f'<polyline points="{pts}" fill="none" stroke="{INK3}" stroke-width="2" '
            f'stroke-linejoin="round" stroke-linecap="round"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="4" fill="{VOLT}"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="6" fill="none" stroke="{CARD}" stroke-width="2"/>'
            f'{dots}</svg>')

rows = "".join(
    f'<tr><td>{ago(r["ts"])}</td><td>{r.get("kind","?")}</td>'
    f'<td style="color:{GOOD if r.get("pass") else BAD}">{"✓ pass" if r.get("pass") else "✕ fail"}</td>'
    f'<td class="num">{r.get("m1b","")}</td></tr>'
    for r in list(reversed(runs))[:25])

out = f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lokt Harness</title><style>
  * {{ margin:0; box-sizing:border-box; }}
  body {{ background:{BG}; color:{INK}; font:15px/1.5 -apple-system,'SF Pro Text',sans-serif; padding:28px 20px; max-width:720px; margin:0 auto; }}
  h1 {{ font-size:26px; font-weight:800; letter-spacing:-0.02em; margin-bottom:2px; }}
  .stamp {{ color:{INK3}; font-size:13px; margin-bottom:22px; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin-bottom:14px; }}
  .tile, .card {{ background:{CARD}; border:1px solid {LINE}; border-radius:16px; padding:16px; }}
  .card {{ margin-bottom:14px; }}
  .micro {{ font-size:11px; font-weight:700; letter-spacing:0.12em; color:{INK3}; text-transform:uppercase; margin-bottom:6px; }}
  .val {{ font-size:24px; font-weight:800; font-variant-numeric:tabular-nums; }}
  .hero {{ font-size:40px; font-weight:800; font-variant-numeric:tabular-nums; }}
  .hero small {{ font-size:14px; font-weight:600; color:{INK2}; }}
  .sub {{ font-size:12px; color:{INK3}; margin-top:4px; }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  td {{ padding:7px 4px; border-top:1px solid {LINE}; color:{INK2}; }}
  td.num {{ text-align:right; font-variant-numeric:tabular-nums; color:{INK}; }}
</style></head><body>
<h1>Lokt Harness</h1>
<div class="stamp">generated {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")} · {len(runs)} runs logged</div>
<div class="grid">
  {tile("Checks", latest("checks"))}
  {tile("Build", latest("build"))}
  {tile("Backend", latest("backend"))}
  <div class="tile"><div class="micro">Pass streak</div><div class="val">{streak}<small style="font-size:13px;color:{INK2}"> runs</small></div><div class="sub">consecutive green checks</div></div>
</div>
<div class="card">
  <div class="micro">M1b migration — direct store-key accesses</div>
  <div class="hero">{m1b_now if m1b_now is not None else "—"} <small>should only go down</small></div>
  {sparkline()}
</div>
<div class="card">
  <div class="micro">Recent runs</div>
  <table>{rows if rows else '<tr><td>none yet — run harness/checks.sh</td></tr>'}</table>
</div>
</body></html>"""

Path("harness/dashboard.html").write_text(out)
print("wrote harness/dashboard.html")
PY

if [ "${1:-}" = "--open" ]; then open harness/dashboard.html; fi
