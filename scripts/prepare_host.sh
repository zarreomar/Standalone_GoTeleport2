#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[prepare-host] %s\n' "$*"
}

die() {
  printf '[prepare-host] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    exec sudo -E "$0" "$@"
  fi
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

PUBLIC_IFACE="${PUBLIC_IFACE:-${HOST_NETWORK_PUBLIC:-ens3}}"
INTERNAL_IFACE="${INTERNAL_IFACE:-${HOST_NETWORK_INTERNAL:-ens4}}"
PUBLIC_IP="${PUBLIC_IP:-}"
INTERNAL_IP="${INTERNAL_IP:-}"
SWARM_SUBNET="${SWARM_SUBNET:-}"
INTERNAL_SUBNET="${INTERNAL_SUBNET:-}"

if [[ -f "$GROUP_VARS_FILE" ]]; then
  PUBLIC_IP="${PUBLIC_IP:-$(yaml_value public_ip "$GROUP_VARS_FILE")}"
  INTERNAL_IP="${INTERNAL_IP:-$(yaml_value internal_ip "$GROUP_VARS_FILE")}"
  SWARM_SUBNET="${SWARM_SUBNET:-$(yaml_value swarm_subnet "$GROUP_VARS_FILE")}"
  INTERNAL_SUBNET="${INTERNAL_SUBNET:-$(yaml_value internal_subnet "$GROUP_VARS_FILE")}"
fi

PUBLIC_IP="${PUBLIC_IP:-}"
INTERNAL_IP="${INTERNAL_IP:-}"
SWARM_SUBNET="${SWARM_SUBNET:-}"
INTERNAL_SUBNET="${INTERNAL_SUBNET:-}"

require_root "$@"

[[ -n "$PUBLIC_IP" ]] || die "PUBLIC_IP is not set and could not be read from ansible/group_vars/all.yml"
[[ -n "$INTERNAL_IP" ]] || die "INTERNAL_IP is not set and could not be read from ansible/group_vars/all.yml"
[[ -n "$SWARM_SUBNET" ]] || die "SWARM_SUBNET is not set and could not be read from ansible/group_vars/all.yml"
[[ -n "$INTERNAL_SUBNET" ]] || die "INTERNAL_SUBNET is not set and could not be read from ansible/group_vars/all.yml"

CODENAME="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
[[ -n "$CODENAME" ]] || die "Could not determine Ubuntu codename"

log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release iproute2 ufw

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine and plugins"
  install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "Docker already present"
fi

log "Enabling Docker service"
systemctl enable --now docker

if ! docker info >/dev/null 2>&1; then
  die "Docker daemon is not responding"
fi

log "Configuring sysctl for container networking"
cat >/etc/sysctl.d/99-goteleport.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null

log "Creating Teleport directories"
install -d -m 0755 /etc/teleport
install -d -m 0755 /var/lib/teleport
install -d -m 0755 /var/lib/teleport/backend
install -d -m 0755 /var/lib/teleport/log

log "Registering routing tables"
if ! grep -qE '^[[:space:]]*100[[:space:]]+public$' /etc/iproute2/rt_tables; then
  printf '%s\n' '100 public' >>/etc/iproute2/rt_tables
fi
if ! grep -qE '^[[:space:]]*200[[:space:]]+internal$' /etc/iproute2/rt_tables; then
  printf '%s\n' '200 internal' >>/etc/iproute2/rt_tables
fi

log "Writing routing helper"
install -d -m 0755 /usr/local/sbin
cat >/etc/teleport/routes.env <<EOF
PUBLIC_IFACE=${PUBLIC_IFACE}
INTERNAL_IFACE=${INTERNAL_IFACE}
PUBLIC_IP=${PUBLIC_IP}
INTERNAL_IP=${INTERNAL_IP}
SWARM_SUBNET=${SWARM_SUBNET}
INTERNAL_SUBNET=${INTERNAL_SUBNET}
EOF
cat >/usr/local/sbin/teleport-routes.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/teleport/routes.env

ensure_route() {
  local table="$1"
  local subnet="$2"
  local iface="$3"
  if ! ip route show table "$table" | grep -Fq "$subnet"; then
    ip route add "$subnet" dev "$iface" table "$table"
  fi
}

ensure_rule() {
  local from_addr="$1"
  local table="$2"
  if ! ip rule list | grep -Fq "from ${from_addr} lookup ${table}"; then
    ip rule add from "$from_addr" table "$table"
  fi
}

ensure_route public "$SWARM_SUBNET" "$PUBLIC_IFACE"
ensure_route internal "$INTERNAL_SUBNET" "$INTERNAL_IFACE"
ensure_rule "$PUBLIC_IP" public
ensure_rule "$INTERNAL_IP" internal
EOF
chmod 0755 /usr/local/sbin/teleport-routes.sh

log "Installing boot-time routing service"
cat >/etc/systemd/system/teleport-routes.service <<'EOF'
[Unit]
Description=Teleport policy routing bootstrap
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/teleport-routes.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable teleport-routes.service

log "Configuring UFW"
if ufw status | grep -qi active; then
  log "UFW is active; ensuring required ports are open"
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 3022/tcp || true
  ufw allow 3023/tcp || true
  ufw allow 3025/tcp || true
else
  log "UFW is inactive; configuring defaults and enabling it safely"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 3022/tcp
  ufw allow 3023/tcp
  ufw allow 3025/tcp
  ufw --force enable
fi

log "Host preparation complete"
log "Next: switch to the ubuntu user and run scripts/prepare_host_ubuntu.sh"
