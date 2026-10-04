#!/usr/bin/env bash
set -euo pipefail

http_status() {
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code}' "$url"
}

record_get() {
  local url="$1" output="$2"
  curl -sS -D "$output.headers" -o "$output.body" "$url" || true
  cat "$output.headers" "$output.body" > "$output"
}

