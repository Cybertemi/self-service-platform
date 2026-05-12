#!/bin/bash

ENV_ID=""
MODE=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --env) ENV_ID="$2"; shift ;;
    --mode) MODE="$2"; shift ;;
  esac
  shift
done

if [ -z "$ENV_ID" ] || [ -z "$MODE" ]; then
  echo "Usage: simulate_outage.sh --env <id> --mode <crash|pause|network|recover|stress>"
  exit 1
fi

# Safety guard - never run against infrastructure
if [[ "$ENV_ID" == *"nginx"* ]] || [[ "$ENV_ID" == *"daemon"* ]] || [[ "$ENV_ID" == "sandbox-nginx" ]]; then
  echo "ERROR: Refusing to simulate against infrastructure container."
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Simulating $MODE on $ENV_ID"

case $MODE in
  crash)
    docker kill "$ENV_ID"
    echo "Container $ENV_ID killed"
    ;;
  pause)
    docker pause "$ENV_ID"
    echo "Container $ENV_ID paused"
    ;;
  network)
    docker network disconnect "$ENV_ID" "$ENV_ID"
    echo "Container $ENV_ID disconnected from network"
    ;;
  recover)
    docker start "$ENV_ID" 2>/dev/null || true
    docker unpause "$ENV_ID" 2>/dev/null || true
    docker network connect "$ENV_ID" "$ENV_ID" 2>/dev/null || true
    echo "Container $ENV_ID recovered"
    ;;
  stress)
    docker exec "$ENV_ID" stress-ng --cpu 2 --timeout 60s &
    echo "Stress test started on $ENV_ID"
    ;;
  *)
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac
