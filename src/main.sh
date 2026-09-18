#!/bin/bash
set -euo pipefail

cmd_install() {
  platform_require

  if [[ -x "$BINARY" ]]; then
    warn "ai-memory já está instalado."
    warn "Use '$PROG update' para atualizar."
    exit 1
  fi

  release_download
  release_extract_to "$ARCHIVE" "${INSTALL_ROOT}.new.$$"
  release_swap_in "${INSTALL_ROOT}.new.$$"
  init_memory
  platform_service_install

  if ! wait_for_server; then
    platform_service_uninstall || true
    release_restore_previous "${OLD_RELEASE:-}" || true
    die "A instalação não pôde iniciar o servidor."
  fi

  agents_configure
  release_discard_old "${OLD_RELEASE:-}"

  success "Instalação concluída."
  echo
  echo "Servidor: ${SERVER_URL}"
  echo "MCP:      ${MCP_URL}"
  echo "Dados:    ${DATA_DIR}"
  echo "Logs:     ${LOG_DIR}"
  echo
  echo "Reinicie os agentes que tenham plugins/extensions carregados no startup."
}

cmd_update() {
  platform_require

  [[ -x "$BINARY" ]] || die "ai-memory não está instalado. Execute '$PROG install'."

  local old_version
  old_version="$(current_version)"
  log "Versão atual: ${old_version:-desconhecida}"

  release_download
  platform_service_uninstall || true

  local new_root="${INSTALL_ROOT}.new.$$"
  release_extract_to "$ARCHIVE" "$new_root"
  release_swap_in "$new_root"

  if ! init_memory; then
    release_restore_previous "${OLD_RELEASE:-}"
    platform_service_install || true
    die "Falha no init; release anterior restaurado."
  fi

  if ! platform_service_install || ! wait_for_server; then
    platform_service_uninstall || true
    release_restore_previous "${OLD_RELEASE:-}"
    platform_service_install || true
    wait_for_server || true
    die "Novo release não iniciou corretamente; release anterior restaurado."
  fi

  if ! agents_configure; then
    warn "A configuração de algum agente falhou; o servidor continua funcionando."
  fi

  release_discard_old "${OLD_RELEASE:-}"

  success "Update concluído."
  echo "  Anterior: ${old_version:-desconhecida}"
  echo "  Atual:    $(current_version)"
}

cmd_uninstall() {
  platform_require

  local purge="${1:-}"
  case "$purge" in
    ""|"--purge") ;;
    *) die "Opção desconhecida para uninstall: $purge" ;;
  esac

  [[ -x "$BINARY" ]] || warn "Binário não encontrado; continuando limpeza."

  if [[ -x "$BINARY" ]]; then
    log "Removendo integrações dos agentes detectados..."
    agents_uninstall
  fi

  log "Parando serviço..."
  platform_service_uninstall || true

  rm -f "$BIN_LINK"

  if [[ "$purge" == "--purge" ]]; then
    log "Apagando release e dados persistentes..."
    rm -rf "$INSTALL_ROOT" "$DATA_DIR" "$CONFIG_DIR"
  else
    log "Removendo binário, mas preservando dados."
    rm -rf "$INSTALL_ROOT"
    echo
    echo "Dados preservados em:"
    echo "  $DATA_DIR"
    echo
    echo "Para remover também os dados:"
    echo "  $PROG uninstall --purge"
  fi

  success "Desinstalação concluída."
}

main() {
  case "${1:-}" in
    install) cmd_install ;;
    update) cmd_update ;;
    status) cmd_status ;;
    doctor) cmd_doctor ;;
    logs) shift; cmd_logs "$@" ;;
    instructions) shift; cmd_instructions "$@" ;;
    uninstall) shift; cmd_uninstall "${1:-}" ;;
    help|-h|--help|"") usage ;;
    *) die "Comando desconhecido: $1. Use '$PROG help'." ;;
  esac
}
