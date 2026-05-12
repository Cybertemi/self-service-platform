#!/bin/bash
set -e

ENV_ID=$1

if [ -z "$ENV_ID" ]; then
  echo "Usage: destroy_env.sh <env-id>"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Destroying $ENV_ID"

# Kill log shipper
PID_FILE="logs/${ENV_ID}/log_shipper.pid"
if [ -f "$PID_FILE" ]; then
  kill "$(cat $PID_FILE)" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

# Stop and remove container
docker stop "$ENV_ID" 2>/dev/null || true
docker rm "$ENV_ID" 2>/dev/null || true

# Remove Docker network
docker network rm "$ENV_ID" 2>/dev/null || true

# Remove nginx config and reload
rm -f "nginx/conf.d/${ENV_ID}.conf"
docker exec sandbox-nginx nginx -s reload 2>/dev/null || true

# Archive logs
if [ -d "logs/${ENV_ID}" ]; then
  mkdir -p "logs/archived"
  mv "logs/${ENV_ID}" "logs/archived/${ENV_ID}"
fi

# Delete state file
rm -f "envs/${ENV_ID}.json"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] $ENV_ID destroyed"
