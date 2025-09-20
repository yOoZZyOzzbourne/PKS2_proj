#!/usr/bin/env bash
set -euo pipefail

RRD="cpu.rrd"
OUTDIR="graphs"

# basic checks
if ! command -v rrdtool >/dev/null 2>&1; then
  echo "rrdtool not found. Install it first (brew install rrdtool)." >&2
  exit 1
fi

if [ ! -f "$RRD" ]; then
  echo "Missing $RRD in current directory. Run from the folder that contains cpu.rrd." >&2
  exit 1
fi

# warn if no data yet
LASTLINE=$(rrdtool lastupdate "$RRD" | tail -n1 || true)
if echo "$LASTLINE" | grep -qi "nan"; then
  echo "Warning: RRD has no data yet (lastupdate shows NaN). Your graphs may be empty." >&2
fi

mkdir -p "$OUTDIR"

# Hourly
rrdtool graph "$OUTDIR/cpu_hour.png" \
  --start -1h --end now \
  --title "CPU Usage - Last Hour" \
  --vertical-label "%" --lower-limit 0 --upper-limit 100 --rigid \
  --units-exponent 0 \
  DEF:cpu="$RRD":cpuused:AVERAGE \
  LINE2:cpu#0072F0:"CPU used"

# Daily
rrdtool graph "$OUTDIR/cpu_day.png" \
  --start -1d --end now \
  --title "CPU Usage - Last Day" \
  --vertical-label "%" --lower-limit 0 --upper-limit 100 --rigid \
  --units-exponent 0 \
  DEF:cpu="$RRD":cpuused:AVERAGE \
  LINE2:cpu#00A651:"CPU used"

# Weekly
rrdtool graph "$OUTDIR/cpu_week.png" \
  --start -1w --end now \
  --title "CPU Usage - Last Week" \
  --vertical-label "%" --lower-limit 0 --upper-limit 100 --rigid \
  --units-exponent 0 \
  DEF:cpu="$RRD":cpuused:AVERAGE \
  LINE2:cpu#E53935:"CPU used"

# Simple HTML dashboard
cat > "$OUTDIR/index.html" <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>CPU Usage Graphs</title>
  <style>
    body{font-family: system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; margin:20px;}
    img{max-width:100%; height:auto;}
  </style>
</head>
<body>
  <h1>CPU Usage</h1>
  <p>Generated: $(date)</p>
  <h2>Last Hour</h2><img src="cpu_hour.png" alt="CPU hour">
  <h2>Last Day</h2><img src="cpu_day.png" alt="CPU day">
  <h2>Last Week</h2><img src="cpu_week.png" alt="CPU week">
</body>
</html>
HTML

echo "Graphs written to $OUTDIR/. Open $OUTDIR/index.html to view."
