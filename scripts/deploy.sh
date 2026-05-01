#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "--- Starting GoTeleport Deployment via Ansible ---"
echo "This wrapper delegates to ansible/main.yml so PostgreSQL, MinIO, and Teleport stay in sync."

exec ansible-playbook -i localhost, -c local "${ROOT_DIR}/ansible/main.yml" "$@"
