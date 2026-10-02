#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env.sh"; write_client_props
kafka kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --command-config "$(props_path)" \
  --create --if-not-exists --topic "$TOPIC" --partitions "$PARTITIONS" --replication-factor "$REPLICAS"
kafka kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --command-config "$(props_path)" --describe --topic "$TOPIC"
