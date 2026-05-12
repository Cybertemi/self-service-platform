#!/bin/bash
set -e

NAME=${1:-"myapp"}
TTL=${2:-1800}

ENV_ID="env-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
PORT=$(shuf -i 4000-9000 -n 1)
CREATED_AT=$(date +%s)
STATE_FILE="envs/${ENV_ID}.json"
NGINX_CONF="nginx/conf.d/${ENV_ID}.conf"

echo "Creating environment: $ENV_ID"

# Create dedicated Docker network
docker network create "$ENV_ID"

# Start app container
docker run -d \
  --name "$ENV_ID" \
  --network "$ENV_ID" \
  --label "sandbox.env=$ENV_ID" \
  -e ENV_ID="$ENV_ID" \
  -p "$PORT:5000" \
  sandbox-app

# Connect to nginx network
docker network connect sandbox-nginx "$ENV_ID"

# Write state file atomically
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << STATEOF
{
  "id": "$ENV_ID",
  "name": "$NAME",
  "created_at": $CREATED_AT,
  "ttl": $TTL,
  "port": $PORT,
  "status": "running"
}
STATEOF
mv "$TEMP_FILE" "$STATE_FILE"

# Write nginx config
cat > "$NGINX_CONF" << NGINXEOF
upstream $ENV_ID {
    server $ENV_ID:5000;
}
server {
    listen 80;
    server_name $ENV_ID.localhost;
    location / {
        proxy_pass http://$ENV_ID;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINXEOF

# Reload nginx
docker exec sandbox-nginx nginx -s reload

# Start log shipping
mkdir -p "logs/${ENV_ID}"
docker logs -f "$ENV_ID" >> "logs/${ENV_ID}/app.log" 2>&1 &
echo $! > "logs/${ENV_ID}/log_shipper.pid"

echo ""
echo "Environment ready!"
echo "  ID:   $ENV_ID"
echo "  Name: $NAME"
echo "  URL:  http://$ENV_ID.localhost"
echo "  Port: $PORT"
echo "  TTL:  ${TTL}s"
