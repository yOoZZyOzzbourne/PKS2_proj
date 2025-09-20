#!/bin/bash
# Take two samples; the first is a warm-up so we use the second.
LINE=$(top -l 2 -n 0 | grep "CPU usage" | tail -1)
# Example: "CPU usage: 5.84% user, 3.16% sys, 0.00% idle"
IDLE=$(echo "$LINE" | awk -F'[, ]+' '{for(i=1;i<=NF;i++){if($i ~ /idle/){print $(i-1); exit}}}')
# Remove the % sign if present
IDLE=${IDLE%%%}
USED=$(awk -v idle="$IDLE" 'BEGIN{printf "%.2f", 100-idle}')
rrdtool update ~/rrd/PKS2_proj/cpu.rrd N:$USED
