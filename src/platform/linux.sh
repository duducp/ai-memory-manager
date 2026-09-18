#!/bin/bash
set -euo pipefail

platform_name() {
  printf 'linux'
}

platform_init_paths() {
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
  local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_state="${XDG_STATE_HOME:-$HOME/.local/state}"

  INSTALL_ROOT="${xdg_data}/ai-memory"
  BIN_DIR="${HOME}/.local/bin"
  BINARY="${INSTALL_ROOT}/ai-memory"
  BIN_LINK="${BIN_DIR}/ai-memory"
  DATA_DIR="${xdg_data}/ai-memory"
  CONFIG_DIR="${xdg_config}/ai-memory"
  LOG_DIR="${xdg_state}/ai-memory"
  SYSTEMD_USER_DIR="${xdg_config}/systemd/user"
  UNIT_FILE="${SYSTEMD_USER_DIR}/ai-memory.service"
  LABEL="ai-memory.service"
  SERVER_HOST="127.0.0.1"
  SERVER_PORT="49374"
  SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"
  MCP_URL="${SERVER_URL}/mcp"
}

platform_require() {
  [[ "$(uname -s)" == "Linux" ]] || die "Este instalador não está rodando no Linux."
  require_cmd curl
  require_cmd tar
  require_cmd systemctl
  require_cmd loginctl
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    die "É necessário sha256sum ou shasum."
  fi
  systemctl --user show-environment >/dev/null 2>&1 ||
    die "systemd --user não está disponível nesta sessão."

  # StandardOutput=append: exige systemd >= 240.
  local sd_version
  sd_version="$(systemctl --version | awk 'NR == 1 {print $2}')"
  [[ "$sd_version" =~ ^[0-9]+$ ]] || sd_version=0
  (( sd_version >= 240 )) || die "É necessário systemd 240 ou superior (encontrado: ${sd_version})."
}

platform_asset_name() {
  printf 'ai-memory-linux-%s.tar.gz' "$ARCH"
}

platform_service_install() {
  mkdir -p "$SYSTEMD_USER_DIR" "$LOG_DIR" "$DATA_DIR" "$CONFIG_DIR"

  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=ai-memory MCP server
After=network.target

[Service]
Type=simple
ExecStart=${BIN_LINK} serve --transport http --bind ${SERVER_HOST}:${SERVER_PORT}
WorkingDirectory=${DATA_DIR}
Restart=always
RestartSec=2
StandardOutput=append:${LOG_DIR}/server.log
StandardError=append:${LOG_DIR}/server.error.log

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now ai-memory.service

  if ! loginctl enable-linger "$(id -un)" >/dev/null 2>&1; then
    warn "Não foi possível habilitar linger; o serviço rodará apenas com sessão ativa."
  fi

  systemctl --user is-active --quiet ai-memory.service ||
    die "O serviço foi registrado, mas não está ativo."
}

platform_service_uninstall() {
  systemctl --user disable --now ai-memory.service >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

platform_service_is_active() {
  systemctl --user is-active --quiet ai-memory.service
}

platform_service_status() {
  if platform_service_is_active; then printf 'RUNNING'; else printf 'NOT RUNNING'; fi
}

platform_extra_doctor_checks() {
  local check="$1"
  "$check" "systemd --user" systemctl --user show-environment
  "$check" "loginctl" command -v loginctl
}
