#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
LISTEN_ADDRESS="${LISTEN_ADDRESS:-127.0.0.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --listen-address) LISTEN_ADDRESS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: healthcheck_jenkins.sh [--port PORT] [--listen-address ADDRESS]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

curl -fsS "http://$LISTEN_ADDRESS:$PORT/api/json" >/dev/null
echo "Jenkins is healthy. URL=http://$LISTEN_ADDRESS:$PORT/"
