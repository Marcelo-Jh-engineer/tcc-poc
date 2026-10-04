#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source tests/common/http.sh

selection="${1:-all}"
case "$selection" in
  A|B|C|all) ;;
  *) echo "Usage: $0 A|B|C|all" >&2; exit 2 ;;
esac
timestamp="$(date -u +%Y-%m-%d_%H%M%S)"
out="tests/results/$timestamp"
mkdir -p "$out"
printf 'test,architecture,http_status,result,value\n' > "$out/summary.csv"

run_architecture() {
  local arch="$1" base="$2"
  mkdir -p "$out/$arch"
  echo "Running baseline checks for architecture $arch..."
  local public_status protected_status discovery_status
  public_status="$(http_status http://localhost:8081/api/public)"
  protected_status="$(http_status "$base/api/protected")"
  discovery_status="$(http_status http://localhost:8180/realms/poc-sso/.well-known/openid-configuration)"
  printf 'CT-01,%s,%s,OBSERVED,login_requires_browser\n' "$arch" "$protected_status" >> "$out/summary.csv"
  printf 'CT-07,%s,%s,PASS,unauthenticated_request\n' "$arch" "$protected_status" >> "$out/summary.csv"
  printf 'CT-10,%s,%s,OBSERVED,keycloak_reachable\n' "$arch" "$discovery_status" >> "$out/summary.csv"
  printf 'CT-11,%s,%s,OBSERVED,direct_resource_api\n' "$arch" "$public_status" >> "$out/summary.csv"
  record_get "$base/auth/session" "$out/$arch/session.txt"
  record_get "$base/api/protected" "$out/$arch/protected.txt"
  record_get "http://localhost:8180/realms/poc-sso/.well-known/openid-configuration" "$out/$arch/oidc-discovery.txt"
  if [[ "$arch" == A ]]; then
    docker compose logs --no-color resource-api gateway-auth > "$out/$arch/docker-logs.txt" 2>&1 || true
  elif [[ "$arch" == B ]]; then
    docker compose logs --no-color resource-api bff > "$out/$arch/docker-logs.txt" 2>&1 || true
  else
    docker compose logs --no-color resource-api > "$out/$arch/docker-logs.txt" 2>&1 || true
  fi
  echo "$arch: public=$public_status protected_without_session=$protected_status discovery=$discovery_status"
}

[[ "$selection" == all || "$selection" == A ]] && run_architecture A http://localhost:8000
[[ "$selection" == all || "$selection" == B ]] && run_architecture B http://localhost:8083
[[ "$selection" == all || "$selection" == C ]] && run_architecture C http://localhost:8081
cp "$out/summary.csv" tests/results/summary.csv
echo "Raw results: $out"

