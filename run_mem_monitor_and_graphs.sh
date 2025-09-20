#!/usr/bin/env bash
set -euo pipefail

# --- config ---
ROOT="$HOME/rrd/PKS2_proj"
RRD="$ROOT/mem.rrd"        # stores used memory in MB
OUT="$ROOT/graphs"
LOG="$ROOT/run_mem.log"
STEP=60                     # collect every 60s
GRAPH_EVERY=300             # regenerate graphs every 5 minutes
HEARTBEAT=300               # tolerate up to 5 min gaps before NaN
# ---------------

mkdir -p "$ROOT" "$OUT"
touch "$LOG"

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG" ; }

# ensure rrdtool exists
if ! command -v rrdtool >/dev/null 2>&1; then
  log "ERROR: rrdtool not found. Install with: brew install rrdtool"
  exit 1
fi

# create mem.rrd if missing (values in MB)
if [ ! -f "$RRD" ]; then
  log "Creating RRD at $RRD (step=$STEP, units=MB)"
  rrdtool create "$RRD" \
    --step "$STEP" \
    DS:memused:GAUGE:$HEARTBEAT:0:U \
    RRA:AVERAGE:0.5:1:1440 \
    RRA:AVERAGE:0.5:5:2016 \
    RRA:AVERAGE:0.5:30:8640
else
  rrdtool tune "$RRD" --heartbeat memused:"$HEARTBEAT" >/dev/null
fi

# ----- memory sampler (macOS) -----
# We'll define "used" ≈ active + inactive + wired + speculative (in MB).
# This is a practical "in-use" view for dashboards (macOS caches aggressively).
get_mem_used_mb() {
  local page_size free active inactive speculative wired total used_bytes used_mb
  page_size=$(sysctl -n hw.pagesize) || return 1

  # vm_stat prints numbers with trailing '.', strip it
  free=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
  active=$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
  inactive=$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')
  speculative=$(vm_stat | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
  wired=$(vm_stat | awk '/Pages wired down/ {gsub(/\./,"",$4); print $4}')

  # sanity check
  [ -n "$page_size" ] && [ -n "$active" ] && [ -n "$inactive" ] && [ -n "$wired" ] && [ -n "$speculative" ] || return 1

  # used pages
  local used_pages=$(( active + inactive + wired + speculative ))
  used_bytes=$(( used_pages * page_size ))

  # to MB with two decimals
  used_mb=$(awk -v b="$used_bytes" 'BEGIN{printf "%.2f", b/1024/1024}')
  echo "$used_mb"
}

gen_graphs() {
  # We store MB in RRD; make a GB view via CDEF
  # Hour
  rrdtool graph "$OUT/mem_hour.png" \
    --start -1h --end now \
    --title "Memory Usage - Last Hour" \
    --vertical-label "GB used" --lower-limit 0 --upper-limit 40 --rigid \
    --width 800 --height 300 \
    DEF:memmb="$RRD":memused:AVERAGE \
    CDEF:memgb=memmb,1024,/ \
    LINE2:memgb#0072F0:"Memory used (GB)" >/dev/null

  # Day
  rrdtool graph "$OUT/mem_day.png" \
    --start -1d --end now \
    --title "Memory Usage - Last Day" \
    --vertical-label "GB used" --lower-limit 0 --upper-limit 40 --rigid \
    --width 800 --height 300 \
    DEF:memmb="$RRD":memused:AVERAGE \
    CDEF:memgb=memmb,1024,/ \
    LINE2:memgb#00A651:"Memory used (GB)" >/dev/null

  # Week
  rrdtool graph "$OUT/mem_week.png" \
    --start -1w --end now \
    --title "Memory Usage - Last Week" \
    --vertical-label "GB used" --lower-limit 0 --upper-limit 40 --rigid \
    --width 800 --height 300 \
    DEF:memmb="$RRD":memused:AVERAGE \
    CDEF:memgb=memmb,1024,/ \
    LINE2:memgb#E53935:"Memory used (GB)" >/dev/null

  # HTML
  cat > "$OUT/index.html" <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Memory Usage Graphs</title>
  <style>
    body{font-family: system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; margin:20px; line-height:1.45;}
    img{max-width:100%; height:auto; border:1px solid #ddd; padding:6px; border-radius:8px; background:#fff; box-shadow:0 1px 4px rgba(0,0,0,.06);}
    .row{display:flex; gap:16px; flex-wrap:wrap;}
    .card{flex:1 1 320px;}
  </style>
</head>
<body>
  <h1>Memory Usage</h1>
  <p>Generated: $(date)</p>
  <div class="row">
    <div class="card"><h2>Last Hour</h2><img src="mem_hour.png" alt="Memory hour"></div>
    <div class="card"><h2>Last Day</h2><img src="mem_day.png" alt="Memory day"></div>
    <div class="card"><h2>Last Week</h2><img src="mem_week.png" alt="Memory week"></div>
  </div>
</body>
</html>
HTML
}

# clean exit
stop=0
trap 'stop=1' INT TERM

log "Starting RAM monitor: update every ${STEP}s, graphs every ${GRAPH_EVERY}s"
last_graph_ts=0

while [ "$stop" -eq 0 ]; do
  if usedmb=$(get_mem_used_mb); then
    if rrdtool update "$RRD" N:"$usedmb" >/dev/null 2>&1; then
      log "OK update memused=${usedmb}MB"
    else
      log "ERROR: rrdtool update failed"
    fi
  else
    log "WARN: could not parse memory from vm_stat; skipping"
  fi

  now=$(date +%s)
  if (( now - last_graph_ts >= GRAPH_EVERY )); then
    log "Generating graphs…"
    gen_graphs
    last_graph_ts=$now
    log "Graphs written to $OUT (open $OUT/index.html)"
  fi

  # sleep to next 60s boundary
  now=$(date +%s)
  sleep_for=$(( STEP - (now % STEP) ))
  (( sleep_for <= 0 )) && sleep_for=$STEP
  sleep "$sleep_for"
done

log "Stopping RAM monitor (CTRL+C). Bye!"
