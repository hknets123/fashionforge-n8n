#!/bin/sh
set -e

echo "========================================="
echo " FashionForge AI - n8n Auto Initializer"
echo "========================================="

# Start n8n in background
echo "[1/5] Starting n8n server..."
n8n start &
N8N_PID=$!

# Wait for n8n to be ready (poll the health endpoint)
echo "[2/5] Waiting for n8n to be ready..."
MAX_WAIT=120
WAITED=0
until wget -qO- http://localhost:${N8N_PORT:-5678}/healthz > /dev/null 2>&1; do
  sleep 2
  WAITED=$((WAITED + 2))
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "WARNING: n8n did not become ready in ${MAX_WAIT}s, checking if it needs setup..."
    break
  fi
  echo "  Waiting... (${WAITED}s)"
done

echo "[3/5] n8n is starting up, waiting for API..."
sleep 10

N8N_URL="http://localhost:${N8N_PORT:-5678}"

# Check if owner account exists by trying to get settings
echo "[3/5] Checking if setup is needed..."
SETUP_CHECK=$(wget -qO- --header="Content-Type: application/json" "${N8N_URL}/api/v1/owner" 2>&1 || true)

if echo "$SETUP_CHECK" | grep -q "not set up"; then
  echo "[4/5] Creating owner account..."
  wget -qO- --post-data='{
    "email": "admin@fashionforge.ai",
    "firstName": "FashionForge",
    "lastName": "Admin",
    "password": "FashionForge2026!"
  }' --header="Content-Type: application/json" "${N8N_URL}/api/v1/owner/setup" 2>&1 || echo "Owner setup may have failed or already exists"
  sleep 3
else
  echo "[4/5] Owner account already exists, skipping..."
fi

# Login to get auth cookie
echo "[4.5/5] Logging in to get API access..."
LOGIN_RESPONSE=$(wget -qO- --post-data='{
  "email": "admin@fashionforge.ai",
  "password": "FashionForge2026!"
}' --header="Content-Type: application/json" --save-cookies /tmp/n8n-cookies.txt "${N8N_URL}/api/v1/login" 2>&1 || echo "")

# Check if workflow already exists
echo "[5/5] Checking for existing workflows..."
WORKFLOWS=$(wget -qO- --load-cookies /tmp/n8n-cookies.txt "${N8N_URL}/api/v1/workflows" 2>&1 || echo "")

if echo "$WORKFLOWS" | grep -q "FashionForge"; then
  echo "✅ FashionForge workflow already exists!"
else
  echo "[5/5] Importing FashionForge workflow..."
  if [ -f /home/node/init-workflow.json ]; then
    wget -qO- --post-file=/home/node/init-workflow.json \
      --header="Content-Type: application/json" \
      --load-cookies /tmp/n8n-cookies.txt \
      "${N8N_URL}/api/v1/workflows" 2>&1 || echo "Workflow import may have failed"
    
    sleep 2
    
    # Try to activate the workflow
    echo "Activating workflow..."
    # Get the workflow ID
    WORKFLOW_LIST=$(wget -qO- --load-cookies /tmp/n8n-cookies.txt "${N8N_URL}/api/v1/workflows" 2>&1 || echo "")
    WORKFLOW_ID=$(echo "$WORKFLOW_LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$WORKFLOW_ID" ]; then
      wget -qO- --method=PATCH --body-data='{"active": true}' \
        --header="Content-Type: application/json" \
        --load-cookies /tmp/n8n-cookies.txt \
        "${N8N_URL}/api/v1/workflows/${WORKFLOW_ID}" 2>&1 || echo "Activation may have failed"
      echo "✅ Workflow imported and activated!"
    else
      echo "⚠️ Could not find workflow ID to activate. Please activate manually."
    fi
  else
    echo "⚠️ Workflow file not found at /home/node/init-workflow.json"
  fi
fi

echo ""
echo "========================================="
echo " FashionForge AI is READY!"
echo " Webhook: /webhook/fashionforge"
echo "========================================="

# Bring n8n back to foreground
wait $N8N_PID
