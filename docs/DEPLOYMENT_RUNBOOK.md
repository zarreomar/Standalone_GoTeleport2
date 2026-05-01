# GoTeleport Docker Swarm Deployment Runbook

**Last Updated:** 2026-05-01  
**Status:** Production Ready  
**Environment:** Docker Swarm with Traefik SSL Proxy

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Network Architecture](#network-architecture)
4. [Deployment Steps](#deployment-steps)
5. [Verification & Testing](#verification--testing)
6. [Troubleshooting](#troubleshooting)
7. [Maintenance](#maintenance)

---

## Overview

This runbook guides the deployment of a **standalone GoTeleport instance** onto a Docker Swarm cluster with:
- **Traefik v3.0** for SSL/TLS termination and HTTP routing
- **Dual-interface networking** (ens3 public, ens4 VPC internal)
- **3-replica deployment** for high availability
- **Persistent storage** for state and audit logs

### Key Components

| Component | Role | Port(s) |
|-----------|------|---------|
| **Traefik** | SSL proxy, HTTP/HTTPS routing | 80, 443, 8080 |
| **GoTeleport Auth** | Authentication service | 3022 |
| **GoTeleport Proxy** | Client proxy service | 3023 (via Traefik on 443) |
| **GoTeleport Health** | Health check endpoint | 3025 |

---

## Prerequisites

### Host Requirements

- **Operating System:** Linux (Ubuntu 22.04 LTS or RHEL 8+)
- **Docker:** v24.0+ with Swarm mode enabled (`docker swarm init`)
- **Network Interfaces:** 
  - `ens3` - Public interface (Internet-facing)
  - `ens4` - VPC/Internal interface (Private network)
- **Storage:** Minimum 50GB available for `/var/lib/teleport`
- **DNS:** Public domain with A record pointing to `ens3` public IP

### Pre-Deployment Checklist

```bash
# Verify Docker Swarm is initialized
docker info | grep Swarm

# Verify network interfaces exist
ip link show ens3
ip link show ens4

# Verify disk space
df -h /var/lib/teleport

# Verify DNS resolution
nslookup goteleport.yourdomain.com
```

### Required Variables

Create a file `deployment.vars` with:

```bash
# Domain and SSL Configuration
PUBLIC_DOMAIN="goteleport.yourdomain.com"
ACME_EMAIL="admin@yourdomain.com"

# Docker Registry (if using private registry)
REGISTRY_URL="your_registry.azurecr.io"
REGISTRY_USERNAME="your_username"
REGISTRY_PASSWORD="your_password"

# Network Configuration
PUBLIC_IP="<ens3 IP address>"
INTERNAL_IP="<ens4 IP address>"
SWARM_SUBNET="10.0.9.0/24"        # Docker Swarm subnet
INTERNAL_SUBNET="172.16.0.0/12"   # VPC internal subnet

# Teleport Configuration
CLUSTER_NAME="goteleport-prod"
ENVIRONMENT="production"
LOG_SEVERITY="INFO"
SESSION_RECORDING="all"
```

---

## Network Architecture

### Interface Binding

```
Public Internet (ens3)
    ↓
    [Traefik:443]  ← HTTPS inbound
    ↓
    [Traefik:80]   ← HTTP inbound (redirect to HTTPS)
    ↓
    Docker Swarm Overlay (teleport-net)
    ↓
    [GoTeleport Services] ← 3 replicas
    ↓
VPC Internal Network (ens4)
    ↓
    Internal clients access via private IP
```

### Routing Tables

The deployment configures routing policies:

```bash
# Public traffic routing table (priority 100)
ip route show table public

# Internal traffic routing table (priority 200)
ip route show table internal
```

---

## Deployment Steps

### Step 1: Prepare the Host

```bash
# Source deployment variables
source deployment.vars

# Create teleport configuration directory
sudo mkdir -p /etc/teleport
sudo mkdir -p /var/lib/teleport/{backend,log}

# Set correct permissions
sudo chown -R 1000:1000 /var/lib/teleport
sudo chmod -R 0755 /var/lib/teleport
```

### Step 2: Build the Docker Image

```bash
# Navigate to the repository root
cd /path/to/Standalone_GoTeleport2

# Build the Docker image
docker build -t ${REGISTRY_URL}/teleport:latest service/

# Push to registry (if using private registry)
docker login ${REGISTRY_URL}
docker push ${REGISTRY_URL}/teleport:latest
```

### Step 3: Initialize Docker Swarm (if not already done)

```bash
# Initialize Swarm mode
docker swarm init --advertise-addr=${PUBLIC_IP}

# Verify manager node
docker node ls
```

### Step 4: Create Docker Networks

```bash
# Create overlay network for Swarm services
docker network create \
  --driver overlay \
  --attachable \
  teleport-net
```

### Step 5: Deploy with Ansible

```bash
# Update ansible/group_vars with your values
cat > ansible/group_vars/all.yml <<EOF
image_name: "${REGISTRY_URL}/teleport:latest"
public_domain: "${PUBLIC_DOMAIN}"
acme_email: "${ACME_EMAIL}"
cluster_name: "${CLUSTER_NAME}"
environment: "${ENVIRONMENT}"
log_severity: "${LOG_SEVERITY}"
host_network_public: "ens3"
host_network_internal: "ens4"
public_ip: "${PUBLIC_IP}"
internal_ip: "${INTERNAL_IP}"
swarm_subnet: "${SWARM_SUBNET}"
internal_subnet: "${INTERNAL_SUBNET}"
EOF

# Run Ansible playbook
ansible-playbook -i localhost, -c local ansible/main.yml
```

### Step 6: Deploy Stack to Swarm

```bash
# Deploy the stack
docker stack deploy -c service/docker-compose.yml gotTeleport_stack

# Verify deployment
docker stack services gotTeleport_stack
docker stack ps gotTeleport_stack
```

### Step 7: Configure Host Routing

```bash
# Create routing policy database entries
sudo tee -a /etc/iproute2/rt_tables <<EOF
100 public
200 internal
EOF

# Add policy rules
sudo ip rule add from ${PUBLIC_IP} table public
sudo ip rule add from ${INTERNAL_IP} table internal

# Add routes
sudo ip route add ${SWARM_SUBNET} dev ens3 table public
sudo ip route add ${INTERNAL_SUBNET} dev ens4 table internal

# Persist routing rules
sudo tee /etc/network/if-up.d/teleport-routes <<'SCRIPT'
#!/bin/bash
source /etc/teleport/routes.env
ip rule add from ${PUBLIC_IP} table public 2>/dev/null
ip rule add from ${INTERNAL_IP} table internal 2>/dev/null
ip route add ${SWARM_SUBNET} dev ens3 table public 2>/dev/null
ip route add ${INTERNAL_SUBNET} dev ens4 table internal 2>/dev/null
SCRIPT

sudo chmod +x /etc/network/if-up.d/teleport-routes
```

---

## Verification & Testing

### Service Health Checks

```bash
# Check service status in Swarm
docker service ls
docker service ps gotTeleport_stack_gotTeleport

# Check Traefik dashboard (local only)
docker service logs gotTeleport_stack_traefik | tail -50

# Verify service health endpoint
curl -k https://${PUBLIC_DOMAIN}:3025/health

# Check container logs
docker service logs gotTeleport_stack_gotTeleport
```

### Network Connectivity Tests

```bash
# Test public interface routing
ping -I ens3 8.8.8.8

# Test internal interface routing
ping -I ens4 10.0.0.1

# Test service accessibility on public domain
curl -k https://${PUBLIC_DOMAIN}

# Test service accessibility on internal network
curl -k https://${INTERNAL_IP}:3023
```

### SSL Certificate Validation

```bash
# Verify ACME certificate generation
docker service logs gotTeleport_stack_traefik | grep -i acme

# Check certificate details
openssl s_client -connect ${PUBLIC_DOMAIN}:443 -servername ${PUBLIC_DOMAIN}

# Verify certificate in Traefik storage
docker exec $(docker ps -f "label=com.docker.swarm.service.name=gotTeleport_stack_traefik" -q) \
  ls -la /etc/traefik/acme.json
```

### Load Testing

```bash
# Simple load test (install if needed: sudo apt-get install apache2-utils)
ab -n 1000 -c 10 https://${PUBLIC_DOMAIN}/

# Check replica distribution
docker service ps gotTeleport_stack_gotTeleport
```

---

## Troubleshooting

### Traefik Not Starting

**Symptom:** Traefik service fails to start or restarts repeatedly

```bash
# Check Traefik logs
docker service logs gotTeleport_stack_traefik

# Common issues:
# - Port 80/443 already in use: lsof -i :80 -i :443
# - Permission denied on Docker socket: ls -l /var/run/docker.sock
# - ACME challenge failure: Verify DNS resolution and firewall rules
```

**Resolution:**
```bash
# Kill processes using ports
sudo lsof -ti:80 | xargs kill -9
sudo lsof -ti:443 | xargs kill -9

# Restart Traefik service
docker service update --force gotTeleport_stack_traefik
```

### GoTeleport Service Unhealthy

**Symptom:** Health check failing, replicas failing to start

```bash
# Check service logs
docker service logs gotTeleport_stack_gotTeleport --tail 100

# Check container directly
docker exec $(docker ps -f "label=com.docker.swarm.service.name=gotTeleport_stack_gotTeleport" -q) \
  curl http://localhost:3025/health
```

**Resolution:**
```bash
# Verify configuration
docker exec $(docker ps -f "label=com.docker.swarm.service.name=gotTeleport_stack_gotTeleport" -q) \
  cat /etc/teleport/teleport.yaml

# Check storage permissions
sudo ls -la /var/lib/teleport

# Increase health check timeout
docker service update gotTeleport_stack_gotTeleport
```

### Network Routing Issues

**Symptom:** Service reachable on public domain but not internal network (or vice versa)

```bash
# Check routing tables
ip rule list
ip route show table public
ip route show table internal

# Verify interface configuration
ip a show ens3
ip a show ens4

# Test connectivity from different interfaces
curl -k --interface ens3 https://${PUBLIC_DOMAIN}
curl -k --interface ens4 https://${INTERNAL_IP}:3023
```

**Resolution:**
```bash
# Reapply routing configuration
source deployment.vars
sudo /etc/network/if-up.d/teleport-routes

# Reload networking
sudo systemctl restart networking
```

### Certificate Renewal Issues

**Symptom:** SSL certificate expired or renewal failed

```bash
# Check ACME logs
docker service logs gotTeleport_stack_traefik | grep -A 5 acme

# Verify DNS resolution
nslookup ${PUBLIC_DOMAIN}

# Check firewall rules (port 80 must be open)
sudo ufw allow 80
sudo ufw allow 443
```

**Resolution:**
```bash
# Force certificate renewal
docker volume rm gotTeleport_stack_traefik-certs || true
docker service update --force gotTeleport_stack_traefik

# Wait for renewal
sleep 60
docker service logs gotTeleport_stack_traefik | grep acme
```

---

## Maintenance

### Regular Tasks

#### Daily
```bash
# Check service health
docker service ps gotTeleport_stack_gotTeleport | grep Running

# Monitor logs for errors
docker service logs gotTeleport_stack_gotTeleport --tail 50 | grep ERROR
```

#### Weekly
```bash
# Review disk usage
df -h /var/lib/teleport

# Backup audit logs
sudo tar -czf /backup/teleport-logs-$(date +%Y%m%d).tar.gz /var/lib/teleport/log/
```

#### Monthly
```bash
# Test failover - drain a node
docker node update --availability drain <node-id>

# Verify service restarts on healthy nodes
docker service ps gotTeleport_stack_gotTeleport

# Restore node
docker node update --availability active <node-id>

# Review and rotate certificates
docker service logs gotTeleport_stack_traefik | grep "certificate" | tail -10
```

### Scaling Services

```bash
# Increase replicas
docker service scale gotTeleport_stack_gotTeleport=5

# Update replica count
docker service update --replicas 5 gotTeleport_stack_gotTeleport

# Verify new replicas
docker service ps gotTeleport_stack_gotTeleport
```

### Updating GoTeleport

```bash
# Build new image version
docker build -t ${REGISTRY_URL}/teleport:v1.2.3 service/
docker push ${REGISTRY_URL}/teleport:v1.2.3

# Update service with new image
docker service update \
  --image ${REGISTRY_URL}/teleport:v1.2.3 \
  gotTeleport_stack_gotTeleport

# Monitor rollout
docker service ps gotTeleport_stack_gotTeleport
```

---

## Emergency Procedures

### Complete Stack Removal

```bash
# WARNING: This removes all service data
docker stack rm gotTeleport_stack

# Remove volumes (if needed)
docker volume rm gotTeleport_stack_traefik-certs
docker volume rm gotTeleport_stack_teleport-data
```

### Service Rollback

```bash
# If new version is problematic
docker service update \
  --image ${REGISTRY_URL}/teleport:previous-version \
  gotTeleport_stack_gotTeleport

# Monitor rollback
docker service ps gotTeleport_stack_gotTeleport
```

---

## Support & Escalation

- **Swarm Health:** `docker node ls`, `docker node inspect <node-id>`
- **Service Status:** `docker service ps`, `docker service logs`
- **Network Debugging:** `docker network inspect`, `ip route show`
- **Firewall Rules:** `sudo ufw status`, `sudo iptables -L -n`

Contact: DevOps Team | Slack: #teleport-deployment
