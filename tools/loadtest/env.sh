# Shared settings. Override any of these in your shell, e.g.  THROUGHPUT=500 ./producer.sh
BOOTSTRAP="${BOOTSTRAP:-demo.kafka.example.com:9094}"   # <tenant>.<domain>:9094
TOPIC="${TOPIC:-loadtest}"
SECURITY="${SECURITY:-ssl}"                              # ssl | scram
KAFKA_USER="${KAFKA_USER:-}"                             # scram only
KAFKA_PASSWORD="${KAFKA_PASSWORD:-}"                     # scram only

# Producer tuning
THROUGHPUT="${THROUGHPUT:-100}"        # messages/sec; -1 = unthrottled. 100 x 10KB ~ 1 MB/s
NUM_RECORDS="${NUM_RECORDS:-1000000000}"   # ~forever at typical rates (115 days at 100/s); Ctrl-C to stop
ACKS="${ACKS:-all}"
LINGER_MS="${LINGER_MS:-5}"
BATCH_SIZE="${BATCH_SIZE:-65536}"
COMPRESSION="${COMPRESSION:-none}"     # none | lz4 | snappy | zstd | gzip
PAYLOAD_FILE="${PAYLOAD_FILE:-$(dirname "$0")/payload-10kb.txt}"

# Consumer tuning
GROUP="${GROUP:-loadtest-consumer}"
MESSAGES="${MESSAGES:-1000000}"        # consumer-perf stops after this many
FETCH_MAX_BYTES="${FETCH_MAX_BYTES:-52428800}"

# Topic creation
PARTITIONS="${PARTITIONS:-6}"
REPLICAS="${REPLICAS:-3}"

# Run Kafka CLI locally if installed, else via container
KAFKA_IMAGE="${KAFKA_IMAGE:-apache/kafka:4.2.1}"
CONTAINER_CLI="${CONTAINER_CLI:-$(command -v podman || command -v docker || true)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

write_client_props() {
  CLIENT_PROPS="$(mktemp)"
  if [ "$SECURITY" = "scram" ]; then
    cat > "$CLIENT_PROPS" <<EOP
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="$KAFKA_USER" password="$KAFKA_PASSWORD";
EOP
  else
    echo "security.protocol=SSL" > "$CLIENT_PROPS"   # public cert: default trust store is enough
  fi
  trap 'rm -f "$CLIENT_PROPS"' EXIT
}

# kafka <tool> args...   (tool is e.g. kafka-producer-perf-test.sh)
kafka() {
  local tool="$1"; shift
  if command -v "$tool" >/dev/null 2>&1; then
    "$tool" "$@"
  elif [ -n "$CONTAINER_CLI" ]; then
    "$CONTAINER_CLI" run --rm -i \
      -v "$CLIENT_PROPS:/client.properties:ro" -v "$HERE:/work:ro" \
      --entrypoint "/opt/kafka/bin/$tool" "$KAFKA_IMAGE" "$@"
  else
    echo "Need Kafka CLI tools on PATH, or podman/docker" >&2; exit 1
  fi
}
# Paths differ between local and container runs
props_path() { if command -v kafka-topics.sh >/dev/null 2>&1; then echo "$CLIENT_PROPS"; else echo /client.properties; fi; }
payload_path() { if command -v kafka-topics.sh >/dev/null 2>&1; then echo "$PAYLOAD_FILE"; else echo "/work/$(basename "$PAYLOAD_FILE")"; fi; }
