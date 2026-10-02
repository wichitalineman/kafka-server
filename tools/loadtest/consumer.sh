#!/usr/bin/env bash
# Reads MESSAGES records as consumer group GROUP and prints MB/s and msgs/s.
set -euo pipefail
. "$(dirname "$0")/env.sh"; write_client_props
echo "bootstrap=$BOOTSTRAP topic=$TOPIC group=$GROUP messages=$MESSAGES"
kafka kafka-consumer-perf-test.sh \
  --bootstrap-server "$BOOTSTRAP" --topic "$TOPIC" --group "$GROUP" \
  --messages "$MESSAGES" --reporting-interval 1000 --show-detailed-stats \
  --consumer.config "$(props_path)" \
  --timeout 60000
