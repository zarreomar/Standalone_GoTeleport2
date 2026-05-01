# Dockerfile for GoTeleport Service
# Based on the SA3 blueprint, this file defines how the GoTeleport application is containerized.

# --- Base Image Selection ---
# Use the official Teleport Community Edition image from Amazon ECR Public.
FROM public.ecr.aws/gravitational/teleport-distroless:18.7.2 AS base

# Copy the reference service configuration into the image as a fallback.
# The Swarm deployment mounts the rendered runtime config over this path.
COPY ./config/teleport.yaml /etc/teleport/teleport.yaml

# Expose all necessary ports for the service to be reachable (Host mapping happens in compose file)
EXPOSE 3022
EXPOSE 3023
EXPOSE 3025
EXPOSE 3080

# --- Entrypoint ---
# Runs Teleport with the bundled configuration file.
ENTRYPOINT ["teleport"]
CMD ["start", "--config=/etc/teleport/teleport.yaml"]
