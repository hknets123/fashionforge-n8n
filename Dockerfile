FROM n8nio/n8n:latest

# Copy the workflow JSON into n8n's import directory
# n8n will auto-import workflows from this directory on startup
USER root
RUN mkdir -p /home/node/.n8n/workflows

COPY fashionforge_workflow.json /home/node/init-workflow.json

# Create an init script that:
# 1. Starts n8n in background
# 2. Waits for n8n to be ready
# 3. Creates owner account via API
# 4. Imports workflow via API
# 5. Activates workflow via API
# 6. Keeps n8n running in foreground
COPY init.sh /home/node/init.sh
RUN chmod +x /home/node/init.sh

USER node

ENTRYPOINT ["/home/node/init.sh"]
