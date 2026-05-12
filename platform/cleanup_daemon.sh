#!/bin/bash

LOG="logs/cleanup.log"
mkdir -p logs

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleanup daemon started" >> "$LOG"

while true; do
  for STATE_FILE in envs/*.json; do
    [ -f "$STATE_FILE" ] || continue

    ENV_ID=$(jq -r '.id' "$STATE_FILE")
    CREATED_AT=$(jq -r '.created_at' "$STATE_FILE")
    TTL=$(jq -r '.ttl' "$STATE_FILE")
    NOW=$(date +%s)
    EXPIRES_AT=$((CREATED_AT + TTL))

    if [ "$NOW" -gt "$EXPIRES_AT" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] TTL expired for $ENV_ID, destroying..." >> "$LOG"
      bash platform/destroy_env.sh "$ENV_ID" >> "$LOG" 2>&1
    fi
  done
  sleep 60
done
