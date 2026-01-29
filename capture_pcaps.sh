#!/usr/bin/env bash
# capture_pcaps.sh <iface> <outdir> <total_duration_secs> <rotate_secs>
# Example:
#   sudo ./capture_pcaps.sh enp3s0 /var/captures 14400 300

set -euo pipefail

IFACE="${1:-}"
OUTDIR="${2:-}"
DURATION="${3:-}"
ROTATE_SECS="${4:-}"

if [[ -z "$IFACE" || -z "$OUTDIR" || -z "$DURATION" || -z "$ROTATE_SECS" ]]; then
  echo "Usage: sudo $0 <iface> <outdir> <total_duration_secs> <rotate_secs>"
  exit 1
fi

COMPRESS=1
MIN_FREE_MB=800

HOST="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"

CAPTURE_DIR="$OUTDIR/${HOST}/capture-$TIMESTAMP"
mkdir -p "$CAPTURE_DIR"
chmod 700 "$CAPTURE_DIR" || true

free_mb=$(df -Pm "$OUTDIR" | awk 'NR==2{print $4}')
if (( free_mb < MIN_FREE_MB )); then
  echo "ERROR: not enough free disk on $OUTDIR (${free_mb}MB)"
  exit 1
fi

cat > "$CAPTURE_DIR/metadata.txt" <<EOF
host=$HOST
iface=$IFACE
start_time_local=$(date -Is)
start_time_epoch=$(date +%s)
total_duration_secs=$DURATION
rotate_secs=$ROTATE_SECS
EOF

echo "Starting capture on $HOST ($IFACE)"
echo "Total duration: $DURATION s, rotation: $ROTATE_SECS s"
echo "Output: $CAPTURE_DIR"

dumpcap -i "$IFACE" \
  -b duration:"$ROTATE_SECS" \
  -a duration:"$DURATION" \
  -w "$CAPTURE_DIR/profinet_${HOST}_${TIMESTAMP}.pcapng" \
  -q &

CAP_PID=$!
echo "$CAP_PID" > "$CAPTURE_DIR/dumpcap.pid"

# Compress closed files (saves disk until your PC pulls them)
if [[ "$COMPRESS" -eq 1 ]] && command -v inotifywait >/dev/null 2>&1; then
  inotifywait -m -e close_write --format '%w%f' "$CAPTURE_DIR" \
    | while read -r f; do
        case "$f" in
          *.pcap|*.pcapng)
            [[ -f "$f.gz" ]] && continue
            gzip -1 "$f" || true
            ;;
        esac
      done &
  echo $! > "$CAPTURE_DIR/compressor.pid"
fi

wait "$CAP_PID" || true

[[ -f "$CAPTURE_DIR/compressor.pid" ]] && kill "$(cat "$CAPTURE_DIR/compressor.pid")" 2>/dev/null || true

echo "Capture finished on $HOST"
