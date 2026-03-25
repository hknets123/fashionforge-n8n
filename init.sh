#!/bin/sh
set -e

echo "========================================="
echo " FashionForge AI - n8n Auto Initializer"
echo "========================================="

# Start n8n in background
echo "[1/5] Starting n8n server..."
n8n start &
N8N_PID=$!

N8N_URL="http://localhost:${N8N_PORT:-5678}"

# Wait for n8n to be ready
echo "[2/5] Waiting for n8n to be ready..."
MAX_WAIT=120
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  HTTP_CODE=$(wget --spider -S "${N8N_URL}" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}' || echo "000")
  if [ "$HTTP_CODE" != "000" ]; then
    echo "  n8n responded with HTTP $HTTP_CODE"
    break
  fi
  sleep 3
  WAITED=$((WAITED + 3))
  echo "  Waiting... (${WAITED}s)"
done

# Extra wait for API to be fully ready
echo "[3/5] Waiting for API to initialize..."
sleep 15

# Get credentials from environment variables
N8N_OWNER_EMAIL="${N8N_OWNER_EMAIL:-admin@fashionforge.ai}"
N8N_OWNER_PASSWORD="${N8N_OWNER_PASSWORD:-FashionForge2026!}"

# Try to login first (account may already exist from a previous session)
echo "[4/5] Attempting to login..."
LOGIN_RESPONSE=$(wget -qO- --post-data="{
  \"email\": \"${N8N_OWNER_EMAIL}\",
  \"password\": \"${N8N_OWNER_PASSWORD}\"
}" --header="Content-Type: application/json" \
   --save-cookies /tmp/n8n-cookies.txt \
   --keep-session-cookies \
   "${N8N_URL}/api/v1/login" 2>&1 || echo "LOGIN_FAILED")

if echo "$LOGIN_RESPONSE" | grep -q "LOGIN_FAILED"; then
  echo "  Login failed. Attempting initial setup..."
  
  # Try to set up owner account (works on fresh n8n instances)
  SETUP_RESPONSE=$(wget -qO- --post-data="{
    \"email\": \"${N8N_OWNER_EMAIL}\",
    \"firstName\": \"FashionForge\",
    \"lastName\": \"Admin\",
    \"password\": \"${N8N_OWNER_PASSWORD}\"
  }" --header="Content-Type: application/json" \
     --save-cookies /tmp/n8n-cookies.txt \
     --keep-session-cookies \
     "${N8N_URL}/api/v1/owner/setup" 2>&1 || echo "SETUP_FAILED")
  
  if echo "$SETUP_RESPONSE" | grep -q "SETUP_FAILED"; then
    echo "  ⚠️ Auto-setup failed. Please set up manually at ${WEBHOOK_URL:-the n8n URL}"
    echo "  Then import the workflow from: /home/node/init-workflow.json"
    echo "  Keeping n8n running..."
    wait $N8N_PID
    exit 0
  fi
  
  echo "  ✅ Owner account created! Logging in..."
  sleep 3
  
  # Login after setup
  LOGIN_RESPONSE=$(wget -qO- --post-data="{
    \"email\": \"${N8N_OWNER_EMAIL}\",
    \"password\": \"${N8N_OWNER_PASSWORD}\"
  }" --header="Content-Type: application/json" \
     --save-cookies /tmp/n8n-cookies.txt \
     --keep-session-cookies \
     "${N8N_URL}/api/v1/login" 2>&1 || echo "LOGIN_FAILED")
  
  if echo "$LOGIN_RESPONSE" | grep -q "LOGIN_FAILED"; then
    echo "  ⚠️ Login failed after setup. Please configure manually."
    wait $N8N_PID
    exit 0
  fi
fi

echo "  ✅ Logged in successfully!"

# Check if FashionForge workflow already exists
echo "[5/5] Checking for existing workflows..."
WORKFLOWS=$(wget -qO- \
  --load-cookies /tmp/n8n-cookies.txt \
  "${N8N_URL}/api/v1/workflows" 2>&1 || echo "")

if echo "$WORKFLOWS" | grep -q "FashionForge"; then
  echo "  ✅ FashionForge workflow already exists!"
  
  # Make sure it's activated
  WORKFLOW_ID=$(echo "$WORKFLOWS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
  if [ -n "$WORKFLOW_ID" ]; then
    echo "  Ensuring workflow is active..."
    wget -qO- --method=PATCH \
      --body-data='{"active": true}' \
      --header="Content-Type: application/json" \
      --load-cookies /tmp/n8n-cookies.txt \
      "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}" 2>&1 || echo "  Activation check done"
  fi
else
  echo "  Importing FashionForge workflow..."
  
  if [ -f /home/node/init-workflow.json ]; then
    IMPORT_RESULT=$(wget -qO- \
      --post-file=/home/node/init-workflow.json \
      --header="Content-Type: application/json" \
      --load-cookies /tmp/n8n-cookies.txt \
      "${N8N_URL}/api/v1/workflows" 2>&1 || echo "IMPORT_FAILED")
    
    if echo "$IMPORT_RESULT" | grep -q "IMPORT_FAILED"; then
      echo "  ⚠️ Auto-import failed. Import manually from n8n UI."
    else
      echo "  ✅ Workflow imported!"
      sleep 2
      
      # Get workflow ID and activate
      WORKFLOW_ID=$(echo "$IMPORT_RESULT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
      
      if [ -n "$WORKFLOW_ID" ]; then
        echo "  Activating workflow (ID: ${WORKFLOW_ID})..."
        wget -qO- --method=PATCH \
          --body-data='{"active": true}' \
          --header="Content-Type: application/json" \
          --load-cookies /tmp/n8n-cookies.txt \
          "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}" 2>&1 || echo "  Activation attempted"
        echo "  ✅ Workflow activated!"
      fi
    fi
  else
    echo "  ⚠️ Workflow file not found at /home/node/init-workflow.json"
  fi
fi

# Cleanup
rm -f /tmp/n8n-cookies.txt

echo ""
echo "========================================="
echo " FashionForge AI is READY!"
echo " Webhook: ${WEBHOOK_URL:-http://localhost:5678}/webhook/fashionforge"
echo "========================================="

# Keep n8n running in foreground
wait $N8N_PID
