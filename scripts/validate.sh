#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== GoTeleport Pre-Deployment Validation ==="

check_cmd() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "✓ $label"
  else
    echo "✗ $label"
  fi
}

echo "[1/8] Required host packages"
check_cmd "ca-certificates" "dpkg -l | grep -q ca-certificates"
check_cmd "curl" "dpkg -l | grep -q curl"
check_cmd "gnupg" "dpkg -l | grep -q gnupg"
check_cmd "lsb-release" "dpkg -l | grep -q lsb-release"
check_cmd "iproute2" "dpkg -l | grep -q iproute2"
check_cmd "ufw" "dpkg -l | grep -q ufw"
check_cmd "python3-venv" "dpkg -l | grep -q python3-venv"

echo "[2/8] Scripts"
check_cmd "prepare_host.sh present" "test -x ${ROOT_DIR}/scripts/prepare_host.sh"
check_cmd "prepare_host_ubuntu.sh present" "test -x ${ROOT_DIR}/scripts/prepare_host_ubuntu.sh"
check_cmd "deploy.sh present" "test -x ${ROOT_DIR}/scripts/deploy.sh"

echo "[3/8] Ansible"
check_cmd "ansible-playbook available" "command -v ansible-playbook"
check_cmd "ansible dry-run passes" "ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote ansible-playbook --check ${ROOT_DIR}/ansible/main.yml -i localhost,"

echo "[4/8] Docker"
check_cmd "docker CLI available" "command -v docker"
check_cmd "docker daemon responsive" "docker info"

echo "[5/8] Host paths"
check_cmd "/var/lib/teleport exists" "test -d /var/lib/teleport"
check_cmd "routing helper present" "test -x /usr/local/sbin/teleport-routes.sh"

echo "[6/8] Compose and config"
check_cmd "service/docker-compose.yml" "test -f ${ROOT_DIR}/service/docker-compose.yml"
check_cmd "config/teleport.yaml" "test -f ${ROOT_DIR}/config/teleport.yaml"

echo "[7/8] Network expectations"
check_cmd "ens3 present" "ip link show ens3"
check_cmd "ens4 present" "ip link show ens4"

echo "[8/8] Summary"
echo "Review any ✗ items before deploying."
