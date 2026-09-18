#!/bin/bash
set -euo pipefail

cmd_install() {
  platform_require

  if [[ -x "$BINARY" ]]; then
    warn "ai-memory já está instalado."
    warn "Use '$PROG update' para atualizar."
    return 1
  fi

  release_download
  release_extract_to "$ARCHIVE" "${INSTALL_ROOT}.new.$$"
  if ! release_swap_in "${INSTALL_ROOT}.new.$$"; then
    rm -rf "${INSTALL_ROOT}.new.$$"
    die "Não foi possível ativar o novo release."
  fi

  if ! init_memory || ! platform_service_install || ! wait_for_server; then
    platform_service_uninstall || true
    if [[ -n "${OLD_RELEASE:-}" && -d "${OLD_RELEASE:-}" ]]; then
      release_restore_previous "$OLD_RELEASE" || true
    else
      rm -rf "$INSTALL_ROOT"
      rm -f "$BIN_LINK"
    fi
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

  local force="false"
  case "${1:-}" in
    "") ;;
    --force) force="true" ;;
    *) die "Opção desconhecida para update: $1" ;;
  esac

  [[ -x "$BINARY" ]] || die "ai-memory não está instalado. Execute '$PROG install'."

  local old_version installed latest
  old_version="$(current_version)"
  installed="$(printf '%s' "$old_version" | awk '{print $NF}')"
  latest="$(latest_version)"
  latest="${latest#v}"

  if [[ "$force" != "true" && -n "$latest" && -n "$installed" && "$latest" == "$installed" ]]; then
    success "ai-memory já está na última versão (${installed}). Use '$PROG update --force' para reinstalar."
    return 0
  fi

  log "Versão atual: ${old_version:-desconhecida}"

  release_download

  local new_root="${INSTALL_ROOT}.new.$$"
  release_extract_to "$ARCHIVE" "$new_root"

  platform_service_uninstall || true
  if ! release_swap_in "$new_root"; then
    rm -rf "$new_root"
    platform_service_install || true
    die "Não foi possível ativar o novo release; release anterior restaurado."
  fi

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

cmd_start() {
  platform_require
  [[ -x "$BINARY" ]] || die "ai-memory não está instalado. Execute '$PROG install'."

  log "Iniciando o serviço..."
  if platform_service_start; then
    wait_for_server || warn "O serviço iniciou, mas o servidor ainda não respondeu."
  else
    die "Não foi possível iniciar o serviço. Verifique '$PROG doctor'."
  fi
}

cmd_stop() {
  platform_require
  log "Parando o serviço..."
  platform_service_stop
  success "Serviço parado."
}

cmd_restart() {
  platform_require
  [[ -x "$BINARY" ]] || die "ai-memory não está instalado. Execute '$PROG install'."

  log "Reiniciando o serviço..."
  if platform_service_restart; then
    wait_for_server || warn "O serviço reiniciou, mas o servidor ainda não respondeu."
  else
    die "Não foi possível reiniciar o serviço. Verifique '$PROG doctor'."
  fi
}

cmd_reset() {
  platform_require
  [[ -x "$BINARY" ]] || die "ai-memory não está instalado. Execute '$PROG install'."

  local assume_yes="false"
  case "${1:-}" in
    "") ;;
    --yes|--force) assume_yes="true" ;;
    *) die "Opção desconhecida para reset: $1" ;;
  esac

  if [[ "$assume_yes" != "true" ]]; then
    if has_tty; then
      warn "Isto apaga TODA a memória do ai-memory (wiki/, db/, raw/). É irreversível."
      local answer=""
      prompt_line answer "Digite 'reset' para confirmar: "
      [[ "$answer" == "reset" ]] || die "Reset cancelado."
    else
      die "Reset requer confirmação. Use '$PROG reset --yes' em modo não interativo."
    fi
  fi

  log "Parando o serviço..."
  platform_service_stop || true

  log "Apagando a memória..."
  "$BINARY" reset --confirm

  log "Iniciando o serviço..."
  if ! platform_service_start || ! wait_for_server; then
    die "A memória foi resetada, mas o servidor não voltou a responder. Verifique '$PROG doctor'."
  fi

  success "Memória resetada; o servidor está no ar."
}

main() {
  case "${1:-}" in
    install) cmd_install ;;
    update) shift; cmd_update "${1:-}" ;;
    status) cmd_status ;;
    doctor) cmd_doctor ;;
    logs) shift; cmd_logs "$@" ;;
    instructions) shift; cmd_instructions "$@" ;;
    uninstall) shift; cmd_uninstall "${1:-}" ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    reset) shift; cmd_reset "${1:-}" ;;
    help|-h|--help) usage ;;
    "")
      if has_tty; then
        cmd_menu
      else
        usage
      fi
      ;;
    *) die "Comando desconhecido: $1. Use '$PROG help'." ;;
  esac
}
