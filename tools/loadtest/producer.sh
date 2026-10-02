#!/usr/bin/env bash
# Sends the payload file over and over at THROUGHPUT msgs/sec. Prints rate/latency every second.
set -euo pipefail
. "$(dirname "$0")/env.sh"; write_client_props
[ -f "$PAYLOAD_FILE" ] || "$HERE/make-payload.sh"
echo "bootstrap=$BOOTSTRAP topic=$TOPIC throughput=$THROUGHPUT msg/s acks=$ACKS compression=$COMPRESSION"
kafka kafka-producer-perf-test.sh \
  --topic "$TOPIC" --num-records "$NUM_RECORDS" --throughput "$THROUGHPUT" \
  --payload-file "$(payload_path)" \
  --producer-props bootstrap.servers="$BOOTSTRAP" acks="$ACKS" linger.ms="$LINGER_MS" \
      batch.size="$BATCH_SIZE" compression.type="$COMPRESSION" \
  --producer.config "$(props_path)"
