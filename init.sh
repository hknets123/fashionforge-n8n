#!/bin/sh
set -e

echo "========================================="
echo " FashionForge AI - n8n Starter"
echo "========================================="
echo ""
echo " Workflow file: /home/node/init-workflow.json"
echo " Import it from n8n UI after first setup."
echo ""
echo "========================================="

# Just start n8n normally
exec n8n start
