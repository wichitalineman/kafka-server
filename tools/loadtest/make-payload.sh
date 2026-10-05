#!/usr/bin/env bash
# Creates payload-10kb.txt: ONE line of exactly 10240 bytes (each line = one message).
# Random base64 text, so compression tests are realistic (repeated bytes would compress to ~nothing).
# Use your own 10KB file instead by setting PAYLOAD_FILE (must be a single line).
set -euo pipefail
out="$(dirname "$0")/payload-10kb.txt"
{ head -c 7680 /dev/urandom | base64 | tr -d '\n' | head -c 10239; echo; } > "$out"
wc -c "$out"
