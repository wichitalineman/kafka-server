#!/usr/bin/env bash
# Runs PRODUCERS parallel unthrottled producers per scenario and prints one summary line per producer.
# Usage: TOPIC=perf-12 PRODUCERS=3 RECORDS=300000 ./perf-sweep.sh
# Scenarios (acks / compression / batch.size / linger.ms) are in the SCENARIOS list below.
set -uo pipefail
. "$(dirname "$0")/env.sh"; write_client_props
[ -f "$PAYLOAD_FILE" ] || "$HERE/make-payload.sh" >/dev/null
PRODUCERS="${PRODUCERS:-3}"
RECORDS="${RECORDS:-100000}"                 # per producer per scenario (10KB each: 100000 = ~1 GB)
SCENARIOS=(
  "all  none 65536   5"
  "all  none 524288  50"
  "all  lz4  524288  50"
  "1    none 524288  50"
  "1    lz4  1048576 100"
)
printf "%-6s %-5s %-8s %-6s | per-producer summary\n" acks comp batch linger
for sc in "${SCENARIOS[@]}"; do
  read -r a c b l <<<"$sc"
  printf "%-6s %-5s %-8s %-6s |\n" "$a" "$c" "$b" "$l"
  tmp="$(mktemp -d)"
  for i in $(seq 1 "$PRODUCERS"); do
    # producer 1 streams live progress to the terminal; every producer's final summary line is kept
    ( kafka kafka-producer-perf-test.sh --topic "$TOPIC" --num-records "$RECORDS" --throughput -1 \
        --payload-file "$(payload_path)" \
        --producer-props bootstrap.servers="$BOOTSTRAP" acks="$a" compression.type="$c" batch.size="$b" linger.ms="$l" \
        --producer.config "$(props_path)" 2>&1 \
      | { if [ "$i" = 1 ]; then tee /dev/stderr; else cat; fi; } | tail -1 > "$tmp/$i" ) &
  done
  wait
  cat "$tmp"/* | sed 's/^/        /'
  rm -rf "$tmp"
done
echo "Now read it back:  TOPIC=$TOPIC MESSAGES=$((PRODUCERS*RECORDS)) GROUP=perf-read ./consumer.sh"
