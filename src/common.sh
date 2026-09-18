#!/bin/bash
set -euo pipefail

REPO="akitaonrails/ai-memory"
PROG="${AI_MEMORY_MANAGER_PROG:-install.sh}"
SCRIPT_VERSION="${SCRIPT_VERSION:-7.0.0}"

TMP_DIR=""

log() {
  printf '\033[1;34m[ai-memory]\033[0m %s\n' "$*"
}

success() {
  printf '\033[1;32m[ai-memory]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[ai-memory]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[ai-memory]\033[0m %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd é obrigatório."
}

expand_home() {
  local p="$1"
  p="${p/#\~/$HOME}"
  printf '%s' "$p"
}

arch_normalize() {
  case "$1" in
    arm64|aarch64) printf 'aarch64' ;;
    x86_64|amd64) printf 'x86_64' ;;
    *) die "Arquitetura não suportada: $1" ;;
  esac
}

current_version() {
  [[ -x "$BINARY" ]] || return 0
  "$BINARY" --version 2>/dev/null | head -n 1 || true
}

sha256_of() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    die "Nenhum verificador SHA-256 disponível (shasum ou sha256sum)."
  fi
}

wait_for_server() {
  local max_attempts=20
  local attempt=1

  log "Aguardando ai-memory responder em ${SERVER_URL}..."

  while (( attempt <= max_attempts )); do
    # /mcp responde não-2xx a um GET simples; qualquer resposta prova que o HTTP está vivo.
    if curl -sS --max-time 2 -o /dev/null \
      -w "%{http_code}" "${MCP_URL}" 2>/dev/null | grep -Eq '^[1-5][0-9][0-9]$'; then
      success "Servidor HTTP está respondendo."
      return 0
    fi

    sleep 1
    attempt=$((attempt + 1))
  done

  warn "O servidor não respondeu após ${max_attempts}s."
  if [[ -f "${LOG_DIR}/server.error.log" ]]; then
    tail -n 20 "${LOG_DIR}/server.error.log" >&2 || true
  fi
  return 1
}
