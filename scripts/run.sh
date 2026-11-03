#!/usr/bin/env bash
# Nạp .env rồi chạy một playbook của một dịch vụ.
#   scripts/run.sh redis preflight
#   scripts/run.sh haproxy setup
#   scripts/run.sh redis clear -e confirm_clear=yes
#   scripts/run.sh redis bundle      # không SSH: sinh bundle/redis/<máy>/install.sh để chép lên và chạy tay
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"

usage() {
  echo "Usage: $0 <redis|haproxy> <preflight|setup|verify|clear|bundle> [ansible-playbook args...]" >&2
  exit 1
}

[ $# -ge 2 ] || usage
SERVICE="$1"
PLAYBOOK="$2"
shift 2

SERVICE_DIR="${ROOT_DIR}/${SERVICE}/ansible"
[ -d "${SERVICE_DIR}" ] || { echo "ERROR: unknown service: ${SERVICE}" >&2; usage; }
[ -f "${SERVICE_DIR}/playbooks/${PLAYBOOK}.yml" ] || { echo "ERROR: unknown playbook: ${PLAYBOOK}" >&2; usage; }

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: ${ENV_FILE} not found. Run: cp .env.example .env && chmod 600 .env, then fill in values." >&2
  exit 1
fi

if grep -nE '=\$\{[A-Z0-9_]+\}' "${ENV_FILE}" >/dev/null; then
  echo "WARNING: ${ENV_FILE} still has unfilled \${...} placeholders:" >&2
  grep -nE '=\$\{[A-Z0-9_]+\}' "${ENV_FILE}" | cut -d= -f1 >&2
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

cd "${SERVICE_DIR}"
exec ansible-playbook "playbooks/${PLAYBOOK}.yml" "$@"
