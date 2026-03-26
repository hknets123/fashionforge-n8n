FROM n8nio/n8n:latest

# Copy the workflow JSON into the container
USER root
COPY fashionforge_workflow.json /home/node/init-workflow.json

# Create a simpler startup script that just starts n8n
# The user will do initial setup once, cron keeps it alive forever after
COPY init.sh /home/node/init.sh
RUN chmod +x /home/node/init.sh

USER node

ENTRYPOINT ["/home/node/init.sh"]
