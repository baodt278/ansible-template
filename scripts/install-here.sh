#!/usr/bin/env bash
# Cài ngay trên máy chủ, khi không SSH/scp được giữa các máy: git clone repo lên máy, tạo .env (dán qua terminal),
# rồi chạy script này. Script nhận ra máy này là máy nào (so IP máy với REDIS_n_IP / HAPROXY_n_IP trong .env),
# sinh cấu hình cho riêng máy này (playbook bundle, không kết nối máy khác) rồi chạy install.sh / verify.sh.
#
#   sudo scripts/install-here.sh redis            # cài Redis trên máy này
#   sudo scripts/install-here.sh redis verify     # kiểm tra cả cụm (sau khi đã cài đủ 3 máy)
#   sudo scripts/install-here.sh haproxy
#   sudo scripts/install-here.sh haproxy verify
#   sudo scripts/install-here.sh vault            # Vault 1 nút (đặt chung máy Redis-1)
#   scripts/install-here.sh redis bundle          # chỉ sinh cấu hình vào bundle/, không cài
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
SERVICE="${1:-}"
ACTION="${2:-install}"

die() { echo "ERROR: $*" >&2; exit 1; }

case "${SERVICE}" in
  redis)   PREFIX=REDIS;   COUNT=3 ;;
  haproxy) PREFIX=HAPROXY; COUNT=2 ;;
  vault)   PREFIX=VAULT;   COUNT=1 ;;
  *) die "Usage: $0 <redis|haproxy|vault> [install|verify|bundle]" ;;
esac
case "${ACTION}" in
  install|verify|bundle) ;;
  *) die "Usage: $0 <redis|haproxy|vault> [install|verify|bundle]" ;;
esac
if [ "${ACTION}" != bundle ] && [ "$(id -u)" -ne 0 ]; then
  die "Run as root: sudo $0 ${SERVICE} ${ACTION}"
fi
[ -f "${ENV_FILE}" ] || die "${ENV_FILE} not found. Create it first (cp .env.example .env, then paste the real values)."
chmod 600 "${ENV_FILE}"

# Nhận ra máy này
set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a
LOCAL_IPS="$(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)"
HOST=""
for n in $(seq 1 "${COUNT}"); do
  var="${PREFIX}_${n}_IP"
  ip="${!var:-}"
  if [ -n "${ip}" ] && grep -qx "${ip}" <<<"${LOCAL_IPS}"; then HOST="${SERVICE}-${n}"; break; fi
done
[ -n "${HOST}" ] || die "This machine's IPs ($(echo "${LOCAL_IPS}" | tr '\n' ' ')) match none of ${PREFIX}_1_IP..${PREFIX}_${COUNT}_IP in .env."
echo "==> This machine is ${HOST}"

# Ansible chỉ cần trên chính máy này (kho Ubuntu, không cần collection)
if ! command -v ansible-playbook >/dev/null; then
  [ "$(id -u)" -eq 0 ] || die "ansible-core is not installed; run once with sudo to install it."
  echo "==> Installing ansible-core"
  DEBIAN_FRONTEND=noninteractive apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q ansible-core
fi

echo "==> Generating configuration for ${HOST}"
"${ROOT_DIR}/scripts/run.sh" "${SERVICE}" bundle --limit "${HOST}"
BUNDLE="${ROOT_DIR}/bundle/${SERVICE}/${HOST}"
[ -f "${BUNDLE}/install.sh" ] || die "Bundle was not generated at ${BUNDLE}."

case "${ACTION}" in
  bundle)  echo "==> Generated ${BUNDLE}" ;;
  install) bash "${BUNDLE}/install.sh" ;;
  verify)  bash "${BUNDLE}/verify.sh" ;;
esac
