#!/bin/bash
# ===============================================================
# GoTeleport Swarm Deployment Orchestration Script
# This script automates the necessary sequence to bring the service online.
# Executed against the host machine with direct Docker access.
# ===============================================================

set -euo pipefail # Exit immediately if a command exits with a non-zero status, unset variable, or pipe fails.

echo "--- Starting GoTeleport Service Deployment Sequence ---"

# 1. BUILD STAGE (If artifacts are not already present)
# If the image does not exist locally, we build it using the official blueprint.
echo "STEP 1/3: Building the Docker image from Dockerfile..."
# IMPORTANT: Ensure you are in the directory containing the Dockerfile when running this.
# docker build -t your_registry/teleport:latest . 

# --- NOTE: For the first run, you MUST build the image first. ---

# 2. INFRASTRUCTURE STACK DEPLOYMENT (SA3 Blueprint)
echo "STEP 2/3: Deploying the stack to Swarm..."
# This command deploys the service defined in docker-compose.yml using the local image.
docker stack deploy -c service/docker-compose.yml gotTeleport_stack

echo "Service deployment initiated successfully. Monitor status below:"
echo "-------------------------------------------------"

# 3. POST-DEPLOYMENT VERIFICATION (SA4 Constraint Check)
echo "STEP 3/3: Verifying Service Health and Host Networking..."

# Check if the service is reachable via the internal network
echo "Verifying service availability on internal network..."
docker service ps gotTeleport_stack_gotTeleport 

# Check the ingress status mapped to the host interfaces (ens3/ens4)
echo "Checking host interfaces configuration..."
# This command would be used to verify the hosts are correctly routing traffic via ens3/ens4 based on the blueprint.
ip a | grep ens3
ip a | grep ens4

echo "Deployment Sequence Complete. Review logs for service status."