#!/bin/bash
set -euo pipefail

# Agent profile:
# name:cli:config_dirs:mode:mcp_client:hook_agent
#
# "hooks" may be:
#   hooks     -> install-mcp + install-hooks
#   mcp       -> MCP only
#   hooks-only -> hooks only
#   managed   -> do not auto-wire
#
# The actual file formats are delegated to ai-memory's installers.
AGENTS=(
  # name:cli:config_dirs:mode:mcp_client:hook_agent
  "claude-code:claude:~/.claude:hooks:claude-code:claude-code"
  "codex:codex:~/.codex:hooks:codex:codex"
  "command-code:command-code:~/.commandcode:hooks:command-code:command-code"
  "devin:devin:~/.devin:hooks:devin:devin"
  "opencode:opencode:~/.config/opencode:hooks:opencode:opencode"
  "cursor:cursor:~/.cursor:hooks:cursor:cursor"
  "gemini-cli:gemini:~/.gemini:hooks:gemini-cli:gemini-cli"
  "omp:omp:~/.omp:hooks:omp:omp"
  "pi:pi:~/.pi:hooks:pi:pi"
  "openclaw:openclaw:~/.openclaw:hooks:openclaw:openclaw"
  "antigravity-cli:antigravity:~/.antigravity|~/.gemini/antigravity:hooks:antigravity-cli:antigravity-cli"
  "grok:grok:~/.grok:hooks:grok:grok"
  "zcode:zcode:~/.zcode:hooks:zcode:zcode"
  "kimi-code:kimi:~/.kimi-code|~/.kimi:hooks:kimi-code:kimi-code"
  "kiro-cli:kiro:~/.kiro:hooks:kiro-cli:kiro-cli"
  "pool:pool:~/.poolside:hooks-only:-:pool"
  "crush:crush:~/.crush:managed:-:-"
  "swival:swival:~/.swival:mcp:swival:-"
  "claude-desktop:-:~/Library/Application Support/Claude:mcp:claude-desktop:-"
  "zed:zed:~/.config/zed:mcp:zed:-"
  "vscode-copilot:code:~/.vscode:mcp:vscode-copilot:-"
  "muse-code:muse:~/.config/muse|~/.muse:mcp:muse:-"
)

DETECTED_AGENTS=()

parse_agent() {
  local entry="$1"
  IFS=":" read -r AGENT_NAME AGENT_CLI AGENT_DIRS AGENT_MODE AGENT_MCP AGENT_HOOK <<< "$entry"
}

agent_detected() {
  local entry="$1"
  parse_agent "$entry"

  # VS Code itself is not proof that Copilot Agent mode is installed.
  # Require a .vscode/mcp.json or a Copilot extension marker instead.
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

  local d
  IFS="|" read -ra DIR_LIST <<< "$AGENT_DIRS"
  for d in "${DIR_LIST[@]}"; do
    d="$(expand_home "$d")"
    if [[ -d "$d" ]]; then
      DETECTION_METHOD="config"
      return 0
    fi
  done

  return 1
}

agents_detect() {
  DETECTED_AGENTS=()

  local entry
  for entry in "${AGENTS[@]}"; do
    if agent_detected "$entry"; then
      DETECTED_AGENTS+=("$entry|$DETECTION_METHOD")
    fi
  done
}

agents_display_name() {
  case "$1" in
    claude-code) echo "Claude Code" ;;
    codex) echo "Codex" ;;
    opencode) echo "OpenCode" ;;
    cursor) echo "Cursor" ;;
    gemini-cli) echo "Gemini CLI" ;;
    antigravity-cli) echo "Antigravity CLI" ;;
    grok) echo "Grok Build CLI" ;;
    openclaw) echo "OpenClaw" ;;
    omp) echo "Oh My Pi / OMP" ;;
    pi) echo "Pi" ;;
    kimi-code) echo "Kimi Code" ;;
    kiro-cli) echo "Kiro CLI" ;;
    command-code) echo "Command Code" ;;
    devin) echo "Devin CLI" ;;
    vscode-copilot) echo "VS Code Copilot" ;;
    zed) echo "Zed" ;;
    claude-desktop) echo "Claude Desktop" ;;
    zcode) echo "ZCode" ;;
    swival) echo "Swival CLI" ;;
    muse-code) echo "Muse Code" ;;
    pool) echo "Pool" ;;
    crush) echo "Crush" ;;
    *) echo "$1" ;;
  esac
}

agent_mcp_client() {
  parse_agent "$1"
  printf '%s' "$AGENT_MCP"
}

agent_hook_agent() {
  parse_agent "$1"
  printf '%s' "$AGENT_HOOK"
}

agent_has_mcp() {
  local name="$1"
  local client
  client="$(agent_mcp_client "$name")"
  [[ "$client" != "-" ]] || return 1

  case "$name" in
    claude-code)
      [[ -f "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" || -f "$HOME/.claude.json" ]] &&
        grep -Fq "$MCP_URL" "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null || \
      [[ -f "$HOME/.claude.json" ]] && grep -Fq "$MCP_URL" "$HOME/.claude.json" 2>/dev/null
      ;;
    opencode)
      [[ -f "$HOME/.config/opencode/opencode.json" ]] && grep -Fq "$MCP_URL" "$HOME/.config/opencode/opencode.json"
      ;;
    codex)
      [[ -f "$HOME/.codex/config.toml" ]] && grep -Fq "$MCP_URL" "$HOME/.codex/config.toml"
      ;;
    cursor)
      [[ -f "$HOME/.cursor/mcp.json" ]] && grep -Fq "$MCP_URL" "$HOME/.cursor/mcp.json"
      ;;
    gemini-cli)
      [[ -f "$HOME/.gemini/settings.json" ]] && grep -Fq "$MCP_URL" "$HOME/.gemini/settings.json"
      ;;
    *)
      local d
      IFS="|" read -ra ds <<< "$AGENT_DIRS"
      for d in "${ds[@]}"; do
        d="$(expand_home "$d")"
        [[ -d "$d" ]] || continue
        if grep -R -Fq "$MCP_URL" "$d" 2>/dev/null; then return 0; fi
      done
      return 1
      ;;
  esac
}

agent_has_hooks() {
  local name="$1"
  parse_agent "$name"
  [[ "$AGENT_HOOK" != "-" ]] || return 1

  # Native staged hooks live here for current releases.
  local hook_root="$HOME/.local/share/ai-memory/hooks/$AGENT_HOOK"
  if [[ -d "$hook_root" ]] && find "$hook_root" -type f -perm -u+x -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  # Generated plugin integrations may not use the staged-hook directory.
  case "$name" in
    opencode) [[ -f "$HOME/.config/opencode/plugins/ai-memory.ts" || -f "$HOME/.config/opencode/plugin/ai-memory.ts" ]] ;;
    pi) [[ -f "$HOME/.pi/agent/extensions/ai-memory-pi.ts" ]] ;;
    omp)
      [[ -f "$HOME/.omp/extensions/ai-memory.ts" ]] || {
        [[ -d "$HOME/.omp" ]] && grep -R -Fq "ai-memory" "$HOME/.omp" 2>/dev/null
      }
      ;;
    openclaw)
      [[ -d "$HOME/.openclaw" ]] && grep -R -Fq "ai-memory" "$HOME/.openclaw" 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

agents_health_line() {
  local entry="$1"
  parse_agent "$entry"
  local name
  name="$(agents_display_name "$AGENT_NAME")"
  case "$AGENT_MODE" in
    hooks)
      if agent_has_mcp "$entry"; then printf '      ✓ MCP configured\n'; else printf '      ✗ MCP not detected\n'; fi
      if agent_has_hooks "$entry"; then printf '      ✓ hooks configured\n'; else printf '      ✗ hooks not detected\n'; fi
      ;;
    mcp)
      if agent_has_mcp "$entry"; then printf '      ✓ MCP configured\n'; else printf '      ✗ MCP not detected\n'; fi
      ;;
    hooks-only)
      if agent_has_hooks "$entry"; then printf '      ✓ hooks configured\n'; else printf '      ! hooks are agent-managed / not locally verifiable\n'; fi
      ;;
    managed)
      printf '      ! managed-only; no direct wiring to verify\n'
      ;;
  esac
}

agents_configure() {
  agents_detect

  if (( ${#DETECTED_AGENTS[@]} == 0 )); then
    warn "Nenhum agente suportado foi detectado."
    return 0
  fi

  log "Agentes detectados:"
  local item entry method name
  for item in "${DETECTED_AGENTS[@]}"; do
    entry="${item%|*}"
    method="${item##*|}"
    parse_agent "$entry"
    name="$(agents_display_name "$AGENT_NAME")"
    log "  - ${name} (${method})"
  done

  for item in "${DETECTED_AGENTS[@]}"; do
    entry="${item%|*}"
    parse_agent "$entry"

    case "$AGENT_MODE" in
      hooks)
        log "Configurando MCP: $(agents_display_name "$AGENT_NAME")"
        "$BINARY" install-mcp \
          --client "$AGENT_NAME" \
          --server-url "$MCP_URL" \
          --apply || warn "MCP falhou para $AGENT_NAME; continuando."

        log "Configurando hooks: $(agents_display_name "$AGENT_NAME")"
        "$BINARY" install-hooks \
          --agent "$AGENT_NAME" \
          --server-url "$SERVER_URL" \
          --apply || warn "Hooks falharam para $AGENT_NAME; continuando."
        ;;
      mcp)
        log "Configurando MCP: $(agents_display_name "$AGENT_NAME")"
        "$BINARY" install-mcp \
          --client "$AGENT_NAME" \
          --server-url "$MCP_URL" \
          --apply || warn "MCP falhou para $AGENT_NAME; continuando."
        ;;
      hooks-only)
        log "Configurando hooks: $(agents_display_name "$AGENT_NAME")"
        "$BINARY" install-hooks \
          --agent "$AGENT_NAME" \
          --server-url "$SERVER_URL" \
          --apply || warn "Hooks falharam para $AGENT_NAME; continuando."
        ;;
      managed)
        warn "$(agents_display_name "$AGENT_NAME") é managed-only; nenhuma configuração automática foi aplicada."
        ;;
    esac
  done
}

agents_uninstall() {
  agents_detect

  if (( ${#DETECTED_AGENTS[@]} == 0 )); then
    log "Nenhum agente detectado para desinstalação."
    return 0
  fi

  local item entry method
  for item in "${DETECTED_AGENTS[@]}"; do
    entry="${item%|*}"
    parse_agent "$entry"

    case "$AGENT_MODE" in
      hooks|mcp|hooks-only)
        log "Removendo integração: $(agents_display_name "$AGENT_NAME")"
        "$BINARY" uninstall \
          --apply \
          --mcp-url "$MCP_URL" \
          >/dev/null 2>&1 || warn "Não foi possível limpar completamente $AGENT_NAME."
        ;;
      managed)
        warn "Pulando $AGENT_NAME: managed-only."
        ;;
    esac
  done

  # ai-memory uninstall is intentionally the authority for ownership-aware
  # cleanup. Do not blindly delete agent config files.
}
