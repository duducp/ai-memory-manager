#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
REPO_SLUG="duducp/ai-memory-manager"
REF="${AI_MEMORY_MANAGER_REF:-main}"
BOOTSTRAP_TMP=""
SRC_DIR=""

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOOT_BLUE=$'\033[1;34m'
  BOOT_RED=$'\033[1;31m'
  BOOT_RESET=$'\033[0m'
else
  BOOT_BLUE=""
  BOOT_RED=""
  BOOT_RESET=""
fi

boot_log() {
  printf '%s[ai-memory]%s %s\n' "$BOOT_BLUE" "$BOOT_RESET" "$*"
}

boot_die() {
  printf '%s[ai-memory]%s %s\n' "$BOOT_RED" "$BOOT_RESET" "$*" >&2
  exit 1
}

cleanup_boot() {
  if [[ -n "$BOOTSTRAP_TMP" && -d "$BOOTSTRAP_TMP" ]]; then
    rm -rf "$BOOTSTRAP_TMP"
  fi
}
trap cleanup_boot EXIT

resolve_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux) PLATFORM="linux" ;;
    *) boot_die "SO não suportado: $(uname -s). Suportados: macOS e Linux." ;;
  esac
}

load_installer() {
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi

  if [[ -n "$script_dir" && -f "$script_dir/src/main.sh" ]]; then
    SRC_DIR="$script_dir/src"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || boot_die "curl é obrigatório."
  command -v tar >/dev/null 2>&1 || boot_die "tar é obrigatório."

  BOOTSTRAP_TMP="$(mktemp -d -t ai-memory-manager.XXXXXX)"
  local url="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REF}"
  boot_log "Baixando instalador (${REF})..."
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 120 \
    -A "ai-memory-manager-bootstrap" "$url" -o "${BOOTSTRAP_TMP}/src.tar.gz"
  tar -xzf "${BOOTSTRAP_TMP}/src.tar.gz" -C "$BOOTSTRAP_TMP"

  local extracted
  extracted="$(find "$BOOTSTRAP_TMP" -maxdepth 1 -type d -name 'ai-memory-manager-*' -print -quit)"
  [[ -n "$extracted" && -f "$extracted/src/main.sh" ]] ||
    boot_die "Falha ao extrair o instalador."
  SRC_DIR="$extracted/src"
}

cleanup_all() {
  cleanup || true
  cleanup_boot
}

resolve_platform
load_installer

# shellcheck source=/dev/null
source "${SRC_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SRC_DIR}/release.sh"
# shellcheck source=/dev/null
source "${SRC_DIR}/agents.sh"
# shellcheck source=/dev/null
source "${SRC_DIR}/commands.sh"
# shellcheck source=/dev/null
source "${SRC_DIR}/platform/${PLATFORM}.sh"
# shellcheck source=/dev/null
source "${SRC_DIR}/main.sh"

trap cleanup_all EXIT

ARCH="$(arch_normalize "$(uname -m)")"
platform_init_paths
main "$@"
