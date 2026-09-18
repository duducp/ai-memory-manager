#!/bin/bash
set -euo pipefail

release_download() {
  TMP_DIR="$(mktemp -d -t ai-memory-install.XXXXXX)"
  chmod 700 "$TMP_DIR"

  local asset
  asset="$(platform_asset_name)"
  local archive="${TMP_DIR}/ai-memory.tar.gz"
  local checksum="${TMP_DIR}/ai-memory.sha256"
  local url="https://github.com/${REPO}/releases/latest/download/${asset}"
  local checksum_url="${url}.sha256"

  log "Baixando release ${asset}..."
  curl -fsSL --retry 3 --retry-delay 1 \
    --connect-timeout 10 --max-time 300 \
    -A "ai-memory-installer" \
    "$url" -o "$archive"

  log "Baixando checksum SHA-256..."
  curl -fsSL --retry 3 --retry-delay 1 \
    --connect-timeout 10 --max-time 60 \
    -A "ai-memory-installer" \
    "$checksum_url" -o "$checksum"

  log "Validando SHA-256..."
  local expected actual
  expected="$(awk '{print $1}' "$checksum" | head -n 1)"
  actual="$(sha256_of "$archive")"

  [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || die "Checksum baixado é inválido."
  [[ "$actual" == "$expected" ]] || die "Falha de integridade: SHA-256 não confere."

  ARCHIVE="$archive"
  success "SHA-256 válido."
}

release_extract_to() {
  local archive="$1"
  local target="$2"
  local staging="${TMP_DIR}/staging"
  local extracted_binary

  [[ -n "${TMP_DIR:-}" ]] || die "TMP_DIR não inicializado (release_download não foi executado)."

  rm -rf "$staging" "$target"
  mkdir -p "$staging" "$target"

  tar -xzf "$archive" -C "$staging"
  extracted_binary="$(find "$staging" -type f -name ai-memory -perm -u+x -print -quit || true)"
  [[ -n "$extracted_binary" ]] || die "O release não contém um binário executável ai-memory."

  cp -R "$(dirname "$extracted_binary")/." "$target/"
  chmod 755 "${target}/ai-memory"
}

release_swap_in() {
  local new_root="$1"
  local old_root="${INSTALL_ROOT}.old.$$"

  rm -rf "$old_root"

  if [[ -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ]]; then
    mv "$INSTALL_ROOT" "$old_root"
  fi

  if ! mv "$new_root" "$INSTALL_ROOT"; then
    if [[ -e "$old_root" ]]; then
      mv "$old_root" "$INSTALL_ROOT" || true
    fi
    return 1
  fi

  mkdir -p "$BIN_DIR"
  ln -sfn "$BINARY" "$BIN_LINK"

  OLD_RELEASE="$old_root"
}

release_restore_previous() {
  local old_root="${1:-}"
  [[ -n "$old_root" && -d "$old_root" ]] || return 0

  warn "Restaurando release anterior..."
  rm -rf "$INSTALL_ROOT"
  mv "$old_root" "$INSTALL_ROOT"
  mkdir -p "$BIN_DIR"
  ln -sfn "$BINARY" "$BIN_LINK"
  success "Release anterior restaurado: $(current_version)"
}

release_discard_old() {
  local old_root="${1:-}"
  if [[ -n "$old_root" && -d "$old_root" ]]; then
    rm -rf "$old_root"
  fi
}

init_memory() {
  log "Inicializando ai-memory..."
  "$BINARY" init
}
