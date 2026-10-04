#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
echo "Stopping the PoC and removing experimental database state..."
docker compose down -v --remove-orphans
echo "Starting the clean environment..."
docker compose up -d --build

services=(postgres keycloak resource-api internal-api bff gateway-auth kong)
for service in "${services[@]}"; do
  echo "Waiting for $service..."
  for attempt in $(seq 1 60); do
    state="$(docker compose ps --format '{{.Service}} {{.Health}}' "$service" 2>/dev/null || true)"
    if [[ "$state" == *"healthy"* ]]; then
      break
    fi
    if [[ "$attempt" == 60 ]]; then
      echo "$service did not become healthy" >&2
      exit 1
    fi
    sleep 2
  done
done
echo "PoC reset completed."

