#!/usr/bin/env bash
# Creates payload-10kb.txt: ONE line of exactly 10240 bytes (each line = one message).
# Use your own 10KB file instead by setting PAYLOAD_FILE (must be a single line).
set -euo pipefail
out="$(dirname "$0")/payload-10kb.txt"
head -c 10239 /dev/zero | tr '\0' 'x' > "$out"; echo >> "$out"
wc -c "$out"
