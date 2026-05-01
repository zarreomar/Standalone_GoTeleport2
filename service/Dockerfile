# Dockerfile for GoTeleport Service
# Based on the SA3 blueprint, this file defines how the GoTeleport application is containerized.

# --- Base Image Selection ---
# IMPORTANT: Using a specific version tag is crucial for reproducibility.
# If the application is built from source, use the golang base image and compile inside the container.
FROM your_registry/teleport:latest AS base

# --- Metadata and Configuration ---
# Set necessary environment variables or use a specific config path
ENV TELEPORT_VERSION=15.4.14
WORKDIR /app

# Copy service configuration files into the image context
COPY ./config/teleport.yaml /etc/teleport/teleport.yaml
COPY ./bin/teleport /usr/local/bin/teleport

# Expose all necessary ports for the service to be reachable (Host mapping happens in compose file)
EXPOSE 3022
EXPOSE 3023
EXPOSE 3025

# --- Health Check Definition ---
# Ensures the container runtime environment is healthy before Swarm attempts to route traffic.
HEALTHCHECK --interval=30s --timeout=10s CMD wget --no-verbose --tries=1 --spider http://localhost:3025/health || exit 1

# --- Entrypoint ---
# Runs the Teleport binary, pointed to the required configuration file.
ENTRYPOINT ["teleport"]
CMD ["start", "--config=/etc/teleport/teleport.yaml"]