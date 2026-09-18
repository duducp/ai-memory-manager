# Multi-Platform Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refatorar o instalador monolítico do ai-memory em módulos compartilhados com um contrato de plataforma, adicionando suporte a Ubuntu/Debian com `systemd --user` sem alterar o comportamento no macOS.

**Architecture:** `install.sh` vira um bootstrap fino que detecta SO/arch, baixa (ou usa localmente) a árvore `src/` e carrega os módulos. `src/platform/{macos,linux}.sh` implementam um contrato fixo; `src/common.sh`, `release.sh`, `agents.sh` e `commands.sh` não conhecem o SO. `src/main.sh` orquestra os fluxos.

**Tech Stack:** Bash 3.2+ (macOS) / Bash 5 (Linux), `curl`, `tar`, `shasum`/`sha256sum`, `launchd`, `systemd --user`, `python3`. Sem suíte de testes (bats fora de escopo); verificação via `shellcheck`, `bash -n` e smoke tests de funções.

**Nota sobre commits:** por instrução explícita do repositório (`AGENTS.md`), **não** faça commit/push durante a execução. Os passos de verificação substituem os passos de commit do fluxo padrão. Só commite se o usuário pedir.

**Spec de referência:** `docs/superpowers/specs/2026-09-18-multi-platform-installer-design.md`

---

## File Structure

| Arquivo | Responsabilidade |
| --- | --- |
| `install.sh` | Bootstrap: detectar SO/arch, localizar/baixar `src/`, carregar módulos, chamar `main`. Sem lógica de instalação. |
| `src/common.sh` | Logging, `die`, `cleanup`, `require_cmd`, `expand_home`, `current_version`, `sha256_of`, `arch_normalize`, `wait_for_server`, constantes `REPO`/`PROG`. |
| `src/release.sh` | `release_download`, `release_extract_to`, `release_swap_in`, `release_restore_previous`, `release_discard_old`, `init_memory`. |
| `src/agents.sh` | Tabela `AGENTS`, detecção, health, `agents_configure`, `agents_uninstall`. |
| `src/commands.sh` | `usage`, `cmd_status`, `cmd_doctor`, `cmd_logs`, `cmd_instructions`. |
| `src/main.sh` | `cmd_install`, `cmd_update`, `cmd_uninstall`, `main` (dispatch). |
| `src/platform/macos.sh` | Paths, `platform_require`, asset, serviço launchd, checks. |
| `src/platform/linux.sh` | Paths XDG, `platform_require`, asset, serviço systemd --user, checks. |
| `.github/workflows/lint.yml` | `shellcheck` + `bash -n` no CI. |
| `README.md` | One-liners macOS/Linux, tabela de paths, ref. |

**Ordem de source (bootstrap):** `common.sh` → `release.sh` → `agents.sh` → `commands.sh` → `platform/<os>.sh` → `main.sh`. Depois: `ARCH`, `platform_init_paths`, `main "$@"`.

**Contrato de plataforma** (implementado por cada `src/platform/<os>.sh`):

`platform_name`, `platform_init_paths`, `platform_require`, `platform_asset_name`,
`platform_service_install`, `platform_service_uninstall`, `platform_service_is_active`,
`platform_service_status`, `platform_extra_doctor_checks`.

---

## Task 1: Módulo comum (`src/common.sh`)

**Files:**
- Create: `src/common.sh`

- [ ] **Step 1: Criar `src/common.sh`**

```bash
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
```

- [ ] **Step 2: Criar `.shellcheckrc`**

O `shellcheck` analisa cada arquivo isoladamente e não enxerga variáveis globais
consumidas em outro módulo, gerando falsos positivos `SC2034`. Desabilite apenas esse
código, com justificativa:

```text
# Variáveis globais (MAIÚSCULAS) são compartilhadas entre módulos via `source`.
# O shellcheck analisa cada arquivo isoladamente e não vê o consumidor, então
# SC2034 ("appears unused") é um falso positivo estrutural neste projeto.
disable=SC2034
```

- [ ] **Step 3: Lint e sintaxe**

Run: `shellcheck src/common.sh && bash -n src/common.sh`
Expected: sem saída (exit 0).

- [ ] **Step 4: Smoke test das funções puras**

Run:
```bash
bash -c 'set -euo pipefail; source src/common.sh; \
  [[ "$(expand_home "~/.x")" == "$HOME/.x" ]] && \
  [[ "$(arch_normalize arm64)" == "aarch64" ]] && \
  [[ "$(arch_normalize x86_64)" == "x86_64" ]] && \
  echo OK'
```
Expected: `OK`

---

## Task 2: Plataforma macOS (`src/platform/macos.sh`)

**Files:**
- Create: `src/platform/macos.sh`

- [ ] **Step 1: Criar `src/platform/macos.sh`**

```bash
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
```

- [ ] **Step 2: Lint e sintaxe**

Run: `shellcheck src/platform/macos.sh && bash -n src/platform/macos.sh`
Expected: sem saída.

- [ ] **Step 3: Smoke test dos paths**

Run:
```bash
bash -c 'set -euo pipefail; ARCH=x86_64; source src/common.sh; source src/platform/macos.sh; \
  platform_init_paths; \
  [[ "$INSTALL_ROOT" == "$HOME/Applications/ai-memory" ]] && \
  [[ "$(platform_asset_name)" == "ai-memory-macos-x86_64.tar.gz" ]] && \
  echo OK'
```
Expected: `OK`

---

## Task 3: Plataforma Linux (`src/platform/linux.sh`)

**Files:**
- Create: `src/platform/linux.sh`

- [ ] **Step 1: Criar `src/platform/linux.sh`**

```bash
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
  require_cmd python3
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    die "É necessário sha256sum ou shasum."
  fi
  systemctl --user show-environment >/dev/null 2>&1 ||
    die "systemd --user não está disponível nesta sessão."
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
```

- [ ] **Step 2: Lint e sintaxe**

Run: `shellcheck src/platform/linux.sh && bash -n src/platform/linux.sh`
Expected: sem saída.

- [ ] **Step 3: Smoke test dos paths e asset**

Run:
```bash
bash -c 'set -euo pipefail; ARCH=aarch64; source src/common.sh; source src/platform/linux.sh; \
  platform_init_paths; \
  [[ "$DATA_DIR" == "$HOME/.local/share/ai-memory" ]] && \
  [[ "$CONFIG_DIR" == "$HOME/.config/ai-memory" ]] && \
  [[ "$LOG_DIR" == "$HOME/.local/state/ai-memory" ]] && \
  [[ "$UNIT_FILE" == "$HOME/.config/systemd/user/ai-memory.service" ]] && \
  [[ "$(platform_asset_name)" == "ai-memory-linux-aarch64.tar.gz" ]] && \
  echo OK'
```
Expected: `OK`

---

## Task 4: Módulo de release (`src/release.sh`)

**Files:**
- Create: `src/release.sh`

- [ ] **Step 1: Criar `src/release.sh`**

```bash
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

  if [[ -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ]]; then
    mv "$INSTALL_ROOT" "$old_root"
  fi

  if ! mv "$new_root" "$INSTALL_ROOT"; then
    if [[ -e "$old_root" ]]; then
      mv "$old_root" "$INSTALL_ROOT" || true
    fi
    die "Não foi possível ativar o novo release."
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
```

- [ ] **Step 2: Lint e sintaxe**

Run: `shellcheck src/release.sh && bash -n src/release.sh`
Expected: sem saída.

- [ ] **Step 3: Smoke test de extração e swap (sem rede)**

Run:
```bash
bash -c '
set -euo pipefail
ARCH=x86_64
source src/common.sh
source src/platform/macos.sh
source src/release.sh
platform_init_paths
INSTALL_ROOT="$(mktemp -d)/app"
BIN_DIR="$(mktemp -d)/bin"
BINARY="$INSTALL_ROOT/ai-memory"
BIN_LINK="$BIN_DIR/ai-memory"
TMP_DIR="$(mktemp -d)"
mkdir -p "$TMP_DIR/src/ai-memory-0.1.0"
printf "#!/bin/sh\necho ai-memory 0.1.0\n" > "$TMP_DIR/src/ai-memory-0.1.0/ai-memory"
chmod +x "$TMP_DIR/src/ai-memory-0.1.0/ai-memory"
tar -czf "$TMP_DIR/rel.tar.gz" -C "$TMP_DIR/src" ai-memory-0.1.0
release_extract_to "$TMP_DIR/rel.tar.gz" "${INSTALL_ROOT}.new.$$"
release_swap_in "${INSTALL_ROOT}.new.$$"
[[ -x "$BINARY" && -L "$BIN_LINK" ]] || exit 1
release_discard_old "${OLD_RELEASE:-}"
echo OK
'
```
Expected: `OK`

---

## Task 5: Módulo de agentes (`src/agents.sh`)

**Files:**
- Create: `src/agents.sh`

- [ ] **Step 1: Mover a tabela e a lógica de agentes do `install.sh` atual**

Copie para `src/agents.sh`, **verbatim**, as funções e o array abaixo do `install.sh` atual, aplicando apenas os renomeamentos desta tabela:

| Origem (`install.sh`) | Destino (`src/agents.sh`) |
| --- | --- |
| array `AGENTS` (linhas 35-59) | array `AGENTS` (sem alteração) |
| global `DETECTED_AGENTS` | global `DETECTED_AGENTS` (sem alteração) |
| `parse_agent` | `parse_agent` (sem alteração) |
| `agent_detected` | `agent_detected` (sem alteração) |
| `detect_agents` | `agents_detect` |
| `agent_display_name` | `agents_display_name` |
| `agent_mcp_client` | `agent_mcp_client` (sem alteração) |
| `agent_hook_agent` | `agent_hook_agent` (sem alteração) |
| `agent_has_mcp` | `agent_has_mcp` (sem alteração) |
| `agent_has_hooks` | `agent_has_hooks` (sem alteração) |
| `agent_health_line` | `agents_health_line` |
| `configure_agents` | `agents_configure` |
| `uninstall_agents` | `agents_uninstall` |

Renomeie também as chamadas internas: `detect_agents` → `agents_detect`, `agent_display_name` → `agents_display_name`, `agent_health_line` → `agents_health_line`.

Adicione o cabeçalho no topo do arquivo:

```bash
#!/bin/bash
set -euo pipefail
```

- [ ] **Step 2: Corrigir a condição do `vscode-copilot` em `agent_detected`**

O `agent_detected` atual tem precedência ambígua de `&&`/`||` na linha do `find`. Substitua o bloco do `vscode-copilot` por:

```bash
  if [[ "$AGENT_NAME" == "vscode-copilot" ]]; then
    local vscode_dir
    # O `~` é intencional: expand_home faz a substituição.
    # shellcheck disable=SC2088
    vscode_dir="$(expand_home "~/.vscode")"
    if [[ -f "$vscode_dir/mcp.json" ]] ||
      { [[ -d "$HOME/.vscode/extensions" ]] &&
        find "$HOME/.vscode/extensions" -maxdepth 1 -type d -iname '*copilot*' -print -quit 2>/dev/null | grep -q .; }; then
      DETECTION_METHOD="config"
      return 0
    fi
  elif [[ "$AGENT_CLI" != "-" ]] && command -v "$AGENT_CLI" >/dev/null 2>&1; then
    DETECTION_METHOD="binary"
    return 0
  fi
```

- [ ] **Step 3: Corrigir SC2155 em `agents_health_line`**

No topo da função `agents_health_line`, troque a declaração-e-atribuição única por duas linhas:

```bash
agents_health_line() {
  local entry="$1"
  parse_agent "$entry"
  local name
  name="$(agents_display_name "$AGENT_NAME")"
  case "$AGENT_MODE" in
```

- [ ] **Step 4: Lint e sintaxe**

Run: `shellcheck src/agents.sh && bash -n src/agents.sh`
Expected: sem saída.

- [ ] **Step 5: Smoke test de parse e display**

Run:
```bash
bash -c 'set -euo pipefail; source src/agents.sh; \
  parse_agent "claude-code:claude:~/.claude:hooks:claude-code:claude-code"; \
  [[ "$AGENT_NAME" == "claude-code" && "$AGENT_MODE" == "hooks" ]] && \
  [[ "$(agents_display_name claude-code)" == "Claude Code" ]] && \
  echo OK'
```
Expected: `OK`

---

## Task 6: Módulo de comandos (`src/commands.sh`)

**Files:**
- Create: `src/commands.sh`

- [ ] **Step 1: Mover `usage`, `logs_command` e `instructions_command`**

Do `install.sh` atual, copie verbatim para `src/commands.sh`:

- `usage` → `usage` (sem renomear)
- `logs_command` → `cmd_logs` (remova o `shift || true` interno da primeira linha do corpo, pois o dispatch já remove `logs`)
- `instructions_command` → `cmd_instructions` (remova o `shift || true` interno da primeira linha do corpo e troque `require_macos` por `platform_require`)

Em `usage`, substitua todas as ocorrências de `$0` por `${PROG}`. Em `cmd_logs` e `cmd_instructions`, substitua `$0` por `${PROG}`.

Adicione o cabeçalho no topo:

```bash
#!/bin/bash
set -euo pipefail
```

- [ ] **Step 2: Substituir `status_command` por `cmd_status`**

Crie `cmd_status` em `src/commands.sh`:

```bash
cmd_status() {
  echo
  echo "ai-memory status"
  echo "================"
  echo

  if [[ -x "$BINARY" ]]; then
    echo "  Binary:      OK"
    echo "  Version:     $(current_version)"
    echo "  Install:     $INSTALL_ROOT"
  else
    echo "  Binary:      NOT INSTALLED"
  fi

  echo "  Service:     $(platform_service_status)"

  if curl -sS --max-time 2 -o /dev/null \
      -w "%{http_code}" "${MCP_URL}" 2>/dev/null | grep -Eq '^[1-5][0-9][0-9]$'; then
    echo "  HTTP:        OK (${SERVER_URL})"
  else
    echo "  HTTP:        NOT RESPONDING (${SERVER_URL})"
  fi

  [[ -d "$DATA_DIR" ]] && echo "  Data:        OK" || echo "  Data:        MISSING"
  [[ -d "$LOG_DIR" ]] && echo "  Logs:        $LOG_DIR" || echo "  Logs:        MISSING"

  echo
  echo "  Detected agents:"
  agents_detect

  if (( ${#DETECTED_AGENTS[@]} == 0 )); then
    echo "    - none"
  else
    local item entry method
    for item in "${DETECTED_AGENTS[@]}"; do
      entry="${item%|*}"
      method="${item##*|}"
      parse_agent "$entry"
      printf '    - %-20s (%s, %s)\n' "$(agents_display_name "$AGENT_NAME")" "$AGENT_MODE" "$method"
    done
  fi

  echo
}
```

- [ ] **Step 3: Substituir `doctor_command` por `cmd_doctor`**

Crie `cmd_doctor` em `src/commands.sh`:

```bash
cmd_doctor() {
  local failures=0

  echo
  echo "ai-memory doctor"
  echo "================"
  echo

  doctor_check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
      printf '  \033[1;32m✓\033[0m %s\n' "$label"
    else
      printf '  \033[1;31m✗\033[0m %s\n' "$label"
      failures=$((failures + 1))
    fi
  }

  doctor_check "ai-memory binary" test -x "$BINARY"
  doctor_check "data directory" test -d "$DATA_DIR"
  doctor_check "service active" platform_service_is_active
  doctor_check "HTTP server" bash -c "curl -sS --max-time 2 -o /dev/null -w '%{http_code}' '${MCP_URL}' | grep -Eq '^[1-5][0-9][0-9]$'"

  platform_extra_doctor_checks doctor_check

  echo
  echo "Agents:"
  agents_detect

  if (( ${#DETECTED_AGENTS[@]} == 0 )); then
    echo "  - nenhum agente detectado"
  else
    local item entry method
    for item in "${DETECTED_AGENTS[@]}"; do
      entry="${item%|*}"
      method="${item##*|}"
      parse_agent "$entry"

      printf '  - %s (%s, detected via %s)\n' "$(agents_display_name "$AGENT_NAME")" "$AGENT_MODE" "$method"
      agents_health_line "$entry"
    done
  fi

  echo
  if (( failures == 0 )); then
    success "Doctor: nenhum problema crítico encontrado."
    return 0
  fi

  warn "Doctor encontrou ${failures} problema(s)."
  return 1
}
```

- [ ] **Step 4: Lint e sintaxe**

Run: `shellcheck src/commands.sh && bash -n src/commands.sh`
Expected: sem saída.

- [ ] **Step 5: Smoke test do usage**

Run:
```bash
bash -c 'set -euo pipefail; ARCH=x86_64; source src/common.sh; source src/platform/macos.sh; \
  platform_init_paths; source src/commands.sh; \
  PROG=install.sh; usage | grep -q "ai-memory macOS installer" && echo OK'
```
Expected: `OK`

---

## Task 7: Orquestração (`src/main.sh`)

**Files:**
- Create: `src/main.sh`

- [ ] **Step 1: Criar `src/main.sh`**

```bash
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
```

- [ ] **Step 2: Lint e sintaxe**

Run: `shellcheck src/main.sh && bash -n src/main.sh`
Expected: sem saída.

---

## Task 8: Bootstrap (`install.sh`)

**Files:**
- Modify: `install.sh` (substituir todo o conteúdo)

- [ ] **Step 1: Substituir o conteúdo de `install.sh`**

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="7.0.0"
REPO_SLUG="duducp/ai-memory-manager"
REF="${AI_MEMORY_MANAGER_REF:-main}"
BOOTSTRAP_TMP=""
SRC_DIR=""

boot_log() {
  printf '\033[1;34m[ai-memory]\033[0m %s\n' "$*"
}

boot_die() {
  printf '\033[1;31m[ai-memory]\033[0m %s\n' "$*" >&2
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
```

- [ ] **Step 2: Tornar executável**

Run: `chmod +x install.sh`
Expected: sem saída.

- [ ] **Step 3: Lint e sintaxe de todos os arquivos**

Run: `shellcheck install.sh src/*.sh src/platform/*.sh && for f in install.sh src/*.sh src/platform/*.sh; do bash -n "$f"; done`
Expected: sem saída.

- [ ] **Step 4: Smoke test do modo checkout (help)**

Run: `bash install.sh help`
Expected: imprime `ai-memory macOS installer v7.0.0` e a lista de comandos, sem tentar instalar nada.

- [ ] **Step 5: Smoke test de comando desconhecido**

Run: `bash install.sh frobnicate; echo "exit=$?"`
Expected: mensagem `Comando desconhecido: frobnicate. Use 'install.sh help'.` e `exit=1`.

---

## Task 9: CI de lint (`.github/workflows/lint.yml`)

**Files:**
- Create: `.github/workflows/lint.yml`

- [ ] **Step 1: Criar o workflow**

```yaml
name: lint

on:
  push:
  pull_request:

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: shellcheck
        run: shellcheck install.sh src/*.sh src/platform/*.sh

      - name: bash syntax
        run: |
          for f in install.sh src/*.sh src/platform/*.sh; do
            bash -n "$f"
          done
```

- [ ] **Step 2: Validar YAML localmente**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/lint.yml')); print('OK')"`
Expected: `OK`

---

## Task 10: Atualizar `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Reescrever a seção de instalação rápida**

Substitua a seção "Instalação rápida (via curl)" por:

````markdown
## Instalação rápida (via curl)

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s install
```

### Linux (Ubuntu 22.04+ / Debian 12+)

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s install
```

O mesmo `install.sh` detecta o sistema operacional. Em execução por pipe é
obrigatório passar o comando após `-s` (por exemplo `bash -s install`); sem isso
o script apenas exibe a ajuda.

Para usar uma branch ou tag específica:

```bash
AI_MEMORY_MANAGER_REF=v7.0.0 curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/v7.0.0/install.sh | AI_MEMORY_MANAGER_REF=v7.0.0 bash -s install
```
````

- [ ] **Step 2: Atualizar a tabela de paths para incluir Linux**

Substitua a seção "O que é instalado" por uma tabela com colunas macOS e Linux:

```markdown
## O que é instalado

| Item | macOS | Linux |
| --- | --- | --- |
| Binário / release | `~/Applications/ai-memory` | `~/.local/share/ai-memory` |
| Link no PATH | `~/.local/bin/ai-memory` | `~/.local/bin/ai-memory` |
| Dados | `~/Library/Application Support/ai-memory` | `~/.local/share/ai-memory` |
| Config | `~/Library/Application Support/ai-memory` | `~/.config/ai-memory` |
| Logs | `~/Library/Logs/ai-memory` | `~/.local/state/ai-memory` |
| Serviço | `~/Library/LaunchAgents/com.ai-memory.server.plist` | `~/.config/systemd/user/ai-memory.service` |

- **Servidor:** `http://127.0.0.1:49374`
- **MCP:** `http://127.0.0.1:49374/mcp`
```

- [ ] **Step 3: Atualizar a estrutura do repositório**

Substitua a seção "Estrutura do repositório" por:

```markdown
## Estrutura do repositório

```
install.sh              # bootstrap (entry do curl)
src/
  main.sh               # dispatch de comandos + fluxos install/update/uninstall
  common.sh             # logging, helpers, sha256, wait_for_server
  release.sh            # download, validação, instalação atômica, rollback
  agents.sh             # detecção e configuração de agentes
  commands.sh           # status, doctor, logs, instructions
  platform/
    macos.sh            # paths, launchd, checks
    linux.sh            # paths, systemd --user, checks
```
```

- [ ] **Step 4: Verificar links e formatação**

Run: `grep -n "install.sh" README.md | head`
Expected: as URLs `raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh` presentes.

- [ ] **Step 5: Nota sobre `.shellcheckrc` no `AGENTS.md`**

Na seção "Execução e verificação" do `AGENTS.md`, adicione após o bloco de comandos:

```markdown
O repositório tem um `.shellcheckrc` que desabilita apenas `SC2034`, porque as
variáveis globais (MAIÚSCULAS) são compartilhadas entre módulos via `source` e o
`shellcheck` analisa cada arquivo isoladamente.
```

---

## Task 11: Verificação final ponta a ponta

**Files:** nenhum (verificação)

- [ ] **Step 1: Lint e sintaxe de tudo**

Run: `shellcheck install.sh src/*.sh src/platform/*.sh && for f in install.sh src/*.sh src/platform/*.sh; do bash -n "$f"; done`
Expected: sem saída.

- [ ] **Step 2: `help` funciona sem variáveis de plataforma faltando**

Run: `bash install.sh help >/dev/null && bash install.sh status >/dev/null 2>&1; echo "status_exit=$?"`
Expected: `help` sem erro; `status` pode retornar 0 ou 1, mas **não** deve falhar com `unbound variable`.

- [ ] **Step 3: `doctor` roda no macOS atual**

Run: `bash install.sh doctor; echo "exit=$?"`
Expected: lista de checks com `✓`/`✗`; sem erro de `unbound variable` nem `command not found`.

- [ ] **Step 4: Verificar que nenhum módulo fora de `platform/` usa `uname`**

Run: `grep -rn "uname" src/common.sh src/release.sh src/agents.sh src/commands.sh src/main.sh || echo "OK"`
Expected: `OK` (apenas `install.sh` e `src/platform/*.sh` podem usar `uname`).

- [ ] **Step 5: Confirmar paridade de comandos com o instalador antigo**

Run: `bash install.sh help | grep -E "install|update|status|doctor|logs|instructions|uninstall"`
Expected: os 7 subcomandos aparecem na ajuda.

---

## Notas de execução

- **Não faça commits** durante a execução (instrução do `AGENTS.md`). Ao final, informe
  o usuário e aguarde pedido explícito para commitar/pushar.
- Após concluir, o instalador antigo é integralmente substituído; o histórico da versão
  monolítica permanece no commit anterior do git.
- Se `shellcheck` não estiver instalado localmente, instale (`brew install shellcheck`
  no macOS) antes das tarefas — é o critério de aceite principal.
