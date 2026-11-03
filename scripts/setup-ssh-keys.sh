#!/usr/bin/env bash
# Chép khóa SSH công khai của máy điều khiển lên các máy Redis / HAProxy (hỏi mật khẩu SSH lần đầu).
#   scripts/setup-ssh-keys.sh            # cả hai nhóm
#   scripts/setup-ssh-keys.sh redis      # chỉ Redis
#   scripts/setup-ssh-keys.sh haproxy    # chỉ HAProxy
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
GROUP="${1:-all}"

[ -f "${ENV_FILE}" ] || { echo "ERROR: ${ENV_FILE} not found" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

: "${ANSIBLE_SSH_USER:?ANSIBLE_SSH_USER is empty in .env}"
: "${ANSIBLE_SSH_KEY_FILE:?ANSIBLE_SSH_KEY_FILE is empty in .env}"
KEY_FILE="${ANSIBLE_SSH_KEY_FILE/#\~/${HOME}}"

hosts=()
case "${GROUP}" in
  redis)   hosts=("${REDIS_1_SSH_HOST:-}" "${REDIS_2_SSH_HOST:-}" "${REDIS_3_SSH_HOST:-}") ;;
  haproxy) hosts=("${HAPROXY_1_SSH_HOST:-}" "${HAPROXY_2_SSH_HOST:-}") ;;
  all)     hosts=("${REDIS_1_SSH_HOST:-}" "${REDIS_2_SSH_HOST:-}" "${REDIS_3_SSH_HOST:-}"
                  "${HAPROXY_1_SSH_HOST:-}" "${HAPROXY_2_SSH_HOST:-}") ;;
  *) echo "Usage: $0 [redis|haproxy|all]" >&2; exit 1 ;;
esac

if [ ! -f "${KEY_FILE}" ]; then
  mkdir -p "$(dirname "${KEY_FILE}")"
  ssh-keygen -t ed25519 -f "${KEY_FILE}" -C "ansible-control" -N ""
fi

for host in "${hosts[@]}"; do
  [ -n "${host}" ] || { echo "ERROR: an SSH host is empty in .env" >&2; exit 1; }
  echo "Copying ${KEY_FILE}.pub to ${ANSIBLE_SSH_USER}@${host}"
  ssh-copy-id -i "${KEY_FILE}.pub" "${ANSIBLE_SSH_USER}@${host}"
done

echo "Done. Check with: scripts/run.sh <redis|haproxy> preflight"
