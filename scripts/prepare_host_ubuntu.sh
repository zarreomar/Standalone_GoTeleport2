#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[prepare-host-ubuntu] %s\n' "$*"
}

die() {
  printf '[prepare-host-ubuntu] ERROR: %s\n' "$*" >&2
  exit 1
}

yaml_value() {
  local key="$1"
  local file="$2"
  awk -F': *' -v key="$key" '
    $1 == key {
      sub(/^"/, "", $2);
      sub(/"$/, "", $2);
      sub(/^'\''/, "", $2);
      sub(/'\''$/, "", $2);
      print $2;
      exit
    }
  ' "$file"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GROUP_VARS_FILE="${ROOT_DIR}/ansible/group_vars/all.yml"

PUBLIC_IP="${PUBLIC_IP:-}"
SWARM_SUBNET="${SWARM_SUBNET:-}"

if [[ -f "$GROUP_VARS_FILE" ]]; then
  PUBLIC_IP="${PUBLIC_IP:-$(yaml_value public_ip "$GROUP_VARS_FILE")}"
  SWARM_SUBNET="${SWARM_SUBNET:-$(yaml_value swarm_subnet "$GROUP_VARS_FILE")}"
fi

[[ -n "$PUBLIC_IP" ]] || die "PUBLIC_IP is not set and could not be read from ansible/group_vars/all.yml"
[[ -n "$SWARM_SUBNET" ]] || die "SWARM_SUBNET is not set and could not be read from ansible/group_vars/all.yml"

if [[ ${EUID:-0} -eq 0 ]]; then
  log "This step should run as the ubuntu user, not root."
fi

if ! docker info >/dev/null 2>&1; then
  die "Docker is not usable for the current user. Re-login after the root prep step so docker group membership takes effect."
fi

if ! docker info 2>/dev/null | grep -qi 'swarm: active'; then
  log "Initializing Docker Swarm"
  docker swarm init --advertise-addr "${PUBLIC_IP}"
else
  log "Docker Swarm is already active"
fi

if ! docker network ls --format '{{.Name}}' | grep -qx teleport-net; then
  log "Creating attachable overlay network teleport-net"
  docker network create --driver overlay --attachable teleport-net
else
  log "Overlay network teleport-net already exists"
fi

log "Ubuntu user prep complete"
log "Next: copy ansible/group_vars/all.yml.example to ansible/group_vars/all.yml if needed, then run ansible-playbook -i localhost, -c local ansible/main.yml"
