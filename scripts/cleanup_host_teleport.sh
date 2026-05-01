#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[cleanup-host] %s\n' "$*"
}

die() {
  printf '[cleanup-host] ERROR: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  read -r -p "${prompt} [y/N] " answer
  [[ "${answer:-N}" =~ ^[Yy]$ ]]
}

if [[ ${EUID:-0} -ne 0 ]]; then
  exec sudo -E "$0" "$@"
fi

if [[ "${1:-}" == "--purge-data" ]]; then
  PURGE_DATA=1
else
  PURGE_DATA=0
fi

log "This will remove old host-side Teleport artifacts:"
log "  - /etc/default/goteleport-routes.env"
log "  - /usr/local/sbin/teleport-routes.sh"
log "  - /etc/systemd/system/teleport-routes.service"
log "  - /etc/sysctl.d/99-goteleport.conf"
log "  - any stale /etc/teleport directory from older runs"
log "  - /var/lib/teleport (only when --purge-data is used)"

if ! confirm "Continue"; then
  log "Aborted"
  exit 0
fi

if systemctl list-unit-files | grep -q '^teleport-routes.service'; then
  systemctl disable --now teleport-routes.service || true
fi
rm -f /etc/systemd/system/teleport-routes.service
systemctl daemon-reload || true

rm -f /usr/local/sbin/teleport-routes.sh
rm -f /etc/default/goteleport-routes.env
rm -f /etc/sysctl.d/99-goteleport.conf
rm -rf /etc/teleport

if [[ "$PURGE_DATA" -eq 1 ]]; then
  rm -rf /var/lib/teleport
else
  log "Skipping /var/lib/teleport removal; pass --purge-data to remove it too"
fi

log "Cleanup complete"
