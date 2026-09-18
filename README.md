# ai-memory-manager

Instalador multi-plataforma para o [ai-memory](https://github.com/akitaonrails/ai-memory), com serviço de usuário (`launchd` no macOS, `systemd --user` no Linux), validação SHA-256, rollback automático em updates e detecção/configuração automática de agentes de IA.

O script baixa a release oficial do ai-memory, instala o binário, registra o servidor HTTP como serviço do usuário e conecta os agentes suportados (MCP + hooks) encontrados na máquina.

## Instalação rápida (via curl)

O mesmo `install.sh` detecta o sistema operacional.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s install
```

### Linux (Ubuntu 22.04+ / Debian 12+)

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s install
```

> Em execução por pipe é obrigatório passar o comando após `-s` (por exemplo `bash -s install`); sem isso o script apenas exibe a ajuda.

Para usar uma branch ou tag específica, defina `AI_MEMORY_MANAGER_REF`:

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | AI_MEMORY_MANAGER_REF=v7.0.0 bash -s install
```

### Forma recomendada (mais segura)

Baixe, inspecione e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh -o install.sh
less install.sh
bash install.sh install
```

## Requisitos

- **macOS** (arm64 ou x86_64): `curl`, `tar`, `shasum` (ou `sha256sum`), `launchctl`, `plutil`, `python3`.
- **Linux** (Ubuntu 22.04+ / Debian 12+, com `systemd --user`): `curl`, `tar`, `sha256sum` (ou `shasum`), `systemctl`, `loginctl`, `python3`.

## Comandos

| Comando | Descrição |
| --- | --- |
| `install` | Baixa a release, instala o binário, cria o serviço do usuário e configura os agentes detectados. |
| `update` | Atualiza para a última release com validação SHA-256 e rollback automático em caso de falha. |
| `status` | Mostra versão, estado do serviço, servidor, dados e agentes detectados. |
| `doctor` | Diagnóstico completo da instalação, com verificações e health dos agentes. |
| `logs` | Acompanha os logs do servidor em tempo real. |
| `instructions` | Atualiza `AGENTS.md` e/ou `CLAUDE.md` (Português ou English). |
| `uninstall` | Remove o ai-memory e as integrações, preservando os dados. |
| `uninstall --purge` | Remove tudo, incluindo a memória persistente. |
| `help` | Exibe a ajuda. |

### Exemplos

```bash
bash install.sh update
bash install.sh status
bash install.sh doctor
bash install.sh logs --error
bash install.sh logs --tail 100
bash install.sh instructions --lang pt-BR --target both
bash install.sh uninstall
```

Via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s status
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s update
```

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

No macOS o LaunchAgent usa `RunAtLoad` e `KeepAlive`. No Linux o unit `systemd --user` usa
`Restart=always` e o instalador tenta habilitar `linger` para o servidor continuar rodando
sem uma sessão aberta.

## Agentes suportados

A detecção usa primeiro o executável do agente e depois seus diretórios de configuração. A configuração real é delegada aos comandos oficiais `install-mcp` / `install-hooks` do ai-memory, respeitando o formato de cada agente.

**MCP + hooks:** Claude Code, Codex, Command Code, Devin, OpenCode, Cursor, Gemini CLI, OMP, Pi, OpenClaw, Antigravity CLI, Grok, ZCode, Kimi Code, Kiro CLI.

**Somente MCP:** Swival, Claude Desktop, Zed, VS Code Copilot, Muse Code.

**Outros:** Pool (hooks-only), Crush (managed-only).

## Segurança

- Verificação de integridade **SHA-256** obrigatória no download da release.
- Substituição de release com retenção da versão anterior até a validação.
- **Rollback automático** se o `init`, o serviço ou o servidor HTTP falharem.
- O `uninstall` é ownership-aware: não apaga arquivos de configuração de agentes cegamente.

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

## Licença

Defina a licença do repositório conforme sua preferência (ex.: MIT).
