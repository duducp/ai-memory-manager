#!/bin/bash
set -euo pipefail

platform_name() {
  printf 'macos'
}

platform_init_paths() {
  INSTALL_ROOT="${HOME}/Applications/ai-memory"
  BIN_DIR="${HOME}/.local/bin"
  BINARY="${INSTALL_ROOT}/ai-memory"
  BIN_LINK="${BIN_DIR}/ai-memory"
  DATA_DIR="${HOME}/Library/Application Support/ai-memory"
  CONFIG_DIR="${DATA_DIR}"
  LOG_DIR="${HOME}/Library/Logs/ai-memory"
  LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
  PLIST="${LAUNCH_AGENTS_DIR}/com.ai-memory.server.plist"
  LABEL="com.ai-memory.server"
  SERVER_HOST="127.0.0.1"
  SERVER_PORT="49374"
  SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"
  MCP_URL="${SERVER_URL}/mcp"
}

platform_require() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Este instalador não está rodando no macOS."
  require_cmd curl
  require_cmd tar
  require_cmd launchctl
  require_cmd plutil
  require_cmd python3
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    die "É necessário shasum ou sha256sum."
  fi
}

platform_asset_name() {
  printf 'ai-memory-macos-%s.tar.gz' "$ARCH"
}

platform_service_install() {
  mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$DATA_DIR"

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${BINARY}</string>
    <string>serve</string>
    <string>--transport</string>
    <string>http</string>
    <string>--bind</string>
    <string>${SERVER_HOST}:${SERVER_PORT}</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${DATA_DIR}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ProcessType</key>
  <string>Background</string>

  <key>StandardOutPath</key>
  <string>${LOG_DIR}/server.log</string>

  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/server.error.log</string>
</dict>
</plist>
EOF

  plutil -lint "$PLIST" >/dev/null || die "LaunchAgent plist inválido."

  local domain
  domain="gui/$(id -u)"
  launchctl bootout "$domain" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$PLIST"
  launchctl enable "${domain}/${LABEL}" >/dev/null 2>&1 || true
  launchctl kickstart -k "${domain}/${LABEL}" >/dev/null 2>&1 || true

  launchctl print "${domain}/${LABEL}" >/dev/null 2>&1 ||
    die "O LaunchAgent foi carregado, mas não aparece no launchctl."
}

platform_service_uninstall() {
  local domain
  domain="gui/$(id -u)"
  launchctl bootout "$domain" "$PLIST" >/dev/null 2>&1 || true
  launchctl disable "${domain}/${LABEL}" >/dev/null 2>&1 || true
  rm -f "$PLIST"
}

platform_service_is_active() {
  launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1
}

platform_service_status() {
  if platform_service_is_active; then printf 'RUNNING'; else printf 'NOT RUNNING'; fi
}

platform_extra_doctor_checks() {
  local check="$1"
  "$check" "macOS" test "$(uname -s)" = "Darwin"
  "$check" "launchctl" command -v launchctl
}
