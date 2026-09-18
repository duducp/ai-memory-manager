#!/bin/bash
set -euo pipefail

REPO="akitaonrails/ai-memory"
PROG="${AI_MEMORY_MANAGER_PROG:-install.sh}"
SCRIPT_VERSION="${SCRIPT_VERSION:-1.0.0}"

TMP_DIR=""

# Cores apenas quando a saída é um terminal e NO_COLOR não está definido.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_BLUE=$'\033[1;34m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'
else
  C_RESET=""
  C_BOLD=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
fi

log() {
  printf '%s[ai-memory]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

success() {
  printf '%s[ai-memory]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

warn() {
  printf '%s[ai-memory]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

die() {
  printf '%s[ai-memory]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
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

# Verdadeiro quando existe um terminal controlador. Necessário porque em
# `curl | bash` o stdin é o próprio script, então prompts precisam de /dev/tty.
has_tty() {
  [[ -c /dev/tty ]] || return 1
  { true < /dev/tty; } 2>/dev/null
}

# prompt_line <var> <texto>: lê uma linha de /dev/tty (ou vazio sem terminal).
prompt_line() {
  local __var="$1"
  local __prompt="$2"
  local __value=""
  if has_tty; then
    read -r -p "$__prompt" __value < /dev/tty || true
  fi
  printf -v "$__var" '%s' "$__value"
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

# Última tag publicada, obtida pelo redirect de /releases/latest (sem usar a API
# e sem consumir rate limit). Retorna vazio se offline ou em caso de erro.
latest_version() {
  local url
  url="$(curl -fsSIL --max-time 3 -o /dev/null -w '%{url_effective}' \
    -A "ai-memory-manager" \
    "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  [[ "$url" == */releases/tag/* ]] || return 0
  printf '%s' "${url##*/releases/tag/}"
}

# Imprime a versão mais recente quando difere da instalada; caso contrário, nada.
available_update() {
  [[ -n "${BINARY:-}" && -x "$BINARY" ]] || return 0

  local installed latest
  installed="$(current_version | awk '{print $NF}')"
  [[ -n "$installed" ]] || return 0

  latest="$(latest_version)"
  [[ -n "$latest" ]] || return 0
  latest="${latest#v}"

  [[ "$latest" == "$installed" ]] && return 0

  printf '%s' "$latest"
}

# Imprime um aviso colorido quando há atualização disponível; caso contrário, nada.
update_notice_line() {
  local latest installed
  latest="$(available_update)"
  [[ -n "$latest" ]] || return 0

  installed="$(current_version | awk '{print $NF}')"
  printf '%sAtualização disponível: %s → %s (use a opção 2)%s\n' \
    "$C_YELLOW" "$installed" "$latest" "$C_RESET"
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

# /mcp responde não-2xx a um GET simples; qualquer resposta prova que o HTTP está vivo.
server_responds() {
  curl -sS --max-time 2 -o /dev/null \
    -w "%{http_code}" "${MCP_URL}" 2>/dev/null | grep -Eq '^[1-5][0-9][0-9]$'
}

wait_for_server() {
  local max_attempts=20
  local attempt=1

  log "Aguardando ai-memory responder em ${SERVER_URL}..."

  while (( attempt <= max_attempts )); do
    if server_responds; then
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
