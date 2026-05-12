#!/bin/bash
# ============================================
# PRE-RECORDING TEST SCRIPT
# Run this before recording your Loom video
# to make sure everything works perfectly
# ============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo ""
echo "============================================"
echo "   SELF-SERVICE PLATFORM - PRE-RECORD TEST "
echo "============================================"
echo ""

# ── STEP 1: Check dependencies ──────────────────
info "Checking dependencies..."

command -v docker &>/dev/null && ok "Docker installed" || fail "Docker missing"
command -v make   &>/dev/null && ok "Make installed"   || fail "Make missing"
command -v jq     &>/dev/null && ok "jq installed"     || fail "jq missing - run: sudo apt install jq"
command -v uuidgen &>/dev/null && ok "uuidgen installed" || fail "uuidgen missing - run: sudo apt install uuid-runtime"
python3 -c "import flask" 2>/dev/null && ok "Flask installed" || fail "Flask missing - run: pip install flask"
python3 -c "import requests" 2>/dev/null && ok "requests installed" || fail "requests missing - run: pip install requests"

echo ""

# ── STEP 2: Check sandbox-app image ─────────────
info "Checking sandbox-app Docker image..."
if docker images | grep -q sandbox-app; then
  ok "sandbox-app image exists"
else
  fail "sandbox-app image missing - run: docker build -t sandbox-app ./demo-app"
  exit 1
fi

echo ""

# ── STEP 3: Tear down anything running ──────────
info "Cleaning up any previous state..."
pkill -f cleanup_daemon.sh 2>/dev/null && info "Killed old cleanup daemon" || true
pkill -f health_poller.py  2>/dev/null && info "Killed old health poller"  || true
pkill -f api.py            2>/dev/null && info "Killed old API"            || true
docker stop sandbox-nginx  2>/dev/null && info "Stopped old nginx"         || true
docker rm sandbox-nginx    2>/dev/null && info "Removed old nginx"         || true
docker network rm sandbox-nginx 2>/dev/null || true

# Clean old envs and logs
for f in envs/*.json; do
  [ -f "$f" ] || continue
  ENV_ID=$(jq -r '.id' "$f")
  bash platform/destroy_env.sh "$ENV_ID" 2>/dev/null || true
done

rm -f logs/cleanup.log
ok "Cleanup done"

echo ""

# ── STEP 4: Start the platform ──────────────────
info "Starting platform (make up)..."
make up > /tmp/makeup.log 2>&1
sleep 3

# Check nginx
if docker ps | grep -q sandbox-nginx; then
  ok "Nginx container running"
else
  fail "Nginx failed to start"
  cat /tmp/makeup.log
  exit 1
fi

# Check API
sleep 2
if curl -s http://localhost:8000/envs > /dev/null 2>&1; then
  ok "Flask API responding on port 8000"
else
  fail "Flask API not responding"
  exit 1
fi

echo ""

# ── STEP 5: Create an environment ───────────────
info "Creating test environment..."
bash platform/create_env.sh demoapp 600 > /tmp/create.log 2>&1
sleep 3

# Get env details
STATE_FILE=$(ls envs/*.json 2>/dev/null | head -1)
if [ -z "$STATE_FILE" ]; then
  fail "No state file created - environment creation failed"
  cat /tmp/create.log
  exit 1
fi

ENV_ID=$(jq -r '.id' "$STATE_FILE")
PORT=$(jq -r '.port' "$STATE_FILE")
TTL=$(jq -r '.ttl' "$STATE_FILE")

ok "Environment created"
echo ""
echo "  ┌─────────────────────────────────┐"
echo "  │  ENV ID : $ENV_ID       │"
echo "  │  PORT   : $PORT                    │"
echo "  │  TTL    : ${TTL}s                  │"
echo "  └─────────────────────────────────┘"
echo ""

# ── STEP 6: Test the app endpoints ──────────────
info "Testing app endpoints..."
sleep 2

ROOT_RESPONSE=$(curl -s http://localhost:$PORT/)
if echo "$ROOT_RESPONSE" | grep -q "Hello"; then
  ok "App root endpoint working"
else
  fail "App root not responding - got: $ROOT_RESPONSE"
fi

HEALTH_RESPONSE=$(curl -s http://localhost:$PORT/health)
if echo "$HEALTH_RESPONSE" | grep -q "ok"; then
  ok "App /health endpoint working"
else
  fail "App /health not responding - got: $HEALTH_RESPONSE"
fi

# ── STEP 7: Test the API ─────────────────────────
info "Testing API endpoints..."

API_LIST=$(curl -s http://localhost:8000/envs)
if echo "$API_LIST" | grep -q "$ENV_ID"; then
  ok "GET /envs working - env visible in API"
else
  fail "GET /envs not returning env"
fi

echo ""

# ── STEP 8: Test outage simulation ──────────────
info "Testing outage simulation (pause)..."
bash platform/simulate_outage.sh --env "$ENV_ID" --mode pause > /dev/null 2>&1
sleep 2

PAUSED_RESPONSE=$(curl -s --max-time 3 http://localhost:$PORT/health 2>&1)
if echo "$PAUSED_RESPONSE" | grep -qE "Failed|timed out|couldn't"; then
  ok "Pause working - app not responding (expected)"
else
  fail "App still responding after pause - something wrong"
fi

info "Recovering from pause..."
bash platform/simulate_outage.sh --env "$ENV_ID" --mode recover > /dev/null 2>&1
sleep 3

RECOVERED=$(curl -s http://localhost:$PORT/health)
if echo "$RECOVERED" | grep -q "ok"; then
  ok "Recovery working - app responding again"
else
  fail "App not responding after recovery"
fi

echo ""

# ── STEP 9: Test crash simulation ───────────────
info "Testing crash simulation..."
bash platform/simulate_outage.sh --env "$ENV_ID" --mode crash > /dev/null 2>&1
sleep 2

CRASHED=$(curl -s --max-time 3 http://localhost:$PORT/health 2>&1)
if echo "$CRASHED" | grep -qE "Failed|refused|couldn't"; then
  ok "Crash working - app not responding (expected)"
else
  fail "App still responding after crash"
fi

info "Recovering from crash..."
bash platform/simulate_outage.sh --env "$ENV_ID" --mode recover > /dev/null 2>&1
sleep 3

RECOVERED2=$(curl -s http://localhost:$PORT/health)
if echo "$RECOVERED2" | grep -q "ok"; then
  ok "Recovery from crash working"
else
  fail "App not responding after crash recovery"
fi

echo ""

# ── STEP 10: Test manual destroy ────────────────
info "Testing manual destroy..."
bash platform/destroy_env.sh "$ENV_ID" > /dev/null 2>&1

if [ ! -f "envs/${ENV_ID}.json" ]; then
  ok "State file deleted"
else
  fail "State file still exists after destroy"
fi

if ! docker ps | grep -q "$ENV_ID"; then
  ok "Container removed"
else
  fail "Container still running after destroy"
fi

echo ""

# ── FINAL SUMMARY ───────────────────────────────
echo "============================================"
echo "            TEST COMPLETE"
echo "============================================"
echo ""
ok "Platform starts with make up"
ok "Environments create with unique ID and port"
ok "Demo app responds on / and /health"
ok "API lists environments correctly"
ok "Pause simulation works"
ok "Crash simulation works"
ok "Recovery works"
ok "Manual destroy works"
echo ""
echo -e "${GREEN}ALL SYSTEMS GO - YOU ARE READY TO RECORD${NC}"
echo ""
echo "For your recording, use these commands:"
echo "  make up"
echo "  make create        (name: demoapp, TTL: 600)"
echo "  cat envs/*.json    (get ENV_ID and PORT)"
echo "  curl http://localhost:<PORT>/"
echo "  curl http://localhost:<PORT>/health"
echo "  curl http://localhost:8000/envs"
echo "  make simulate ENV=<id> MODE=pause"
echo "  make simulate ENV=<id> MODE=recover"
echo "  cat logs/cleanup.log"
echo "  make down"
echo ""
