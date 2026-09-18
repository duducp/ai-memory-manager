# ai-memory-manager

Instalador macOS para o [ai-memory](https://github.com/akitaonrails/ai-memory), com serviço `launchd`, validação SHA-256, rollback automático em updates e detecção/configuração automática de agentes de IA.

O script baixa a release oficial do ai-memory, instala o binário, registra o servidor HTTP como LaunchAgent e conecta os agentes suportados (MCP + hooks) encontrados na máquina.

## Instalação rápida (via curl)

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh | bash -s install
```

> O script é um wrapper com subcomandos. Ao executá-lo por `curl | bash` é obrigatório passar o comando desejado após `-s` (por exemplo `bash -s install`), caso contrário ele apenas exibe a ajuda.

### Forma recomendada (mais segura)

Baixe, inspecione e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/duducp/ai-memory-manager/main/install.sh -o install.sh
less install.sh
bash install.sh install
```

## Requisitos

- macOS (arm64 ou x86_64)
- `curl`, `tar`, `shasum`, `launchctl`
- `python3` (apenas para o subcomando `instructions`)

## Comandos

| Comando | Descrição |
| --- | --- |
| `install` | Baixa a release, instala o binário, cria o LaunchAgent e configura os agentes detectados. |
| `update` | Atualiza para a última release com validação SHA-256 e rollback automático em caso de falha. |
| `status` | Mostra versão, estado do LaunchAgent, servidor, dados e agentes detectados. |
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

| Item | Caminho |
| --- | --- |
| Binário / release | `~/Applications/ai-memory` |
| Link no PATH | `~/.local/bin/ai-memory` |
| Dados e config | `~/Library/Application Support/ai-memory` |
| LaunchAgent | `~/Library/LaunchAgents/com.ai-memory.server.plist` |
| Logs | `~/Library/Logs/ai-memory` |

- **Servidor:** `http://127.0.0.1:49374`
- **MCP:** `http://127.0.0.1:49374/mcp`
- **Label do serviço:** `com.ai-memory.server`

O LaunchAgent usa `RunAtLoad` e `KeepAlive`, mantendo o servidor ativo e reiniciando-o automaticamente.

## Agentes suportados

A detecção usa primeiro o executável do agente e depois seus diretórios de configuração. A configuração real é delegada aos comandos oficiais `install-mcp` / `install-hooks` do ai-memory, respeitando o formato de cada agente.

**MCP + hooks:** Claude Code, Codex, Command Code, Devin, OpenCode, Cursor, Gemini CLI, OMP, Pi, OpenClaw, Antigravity CLI, Grok, ZCode, Kimi Code, Kiro CLI.

**Somente MCP:** Swival, Claude Desktop, Zed, VS Code Copilot, Muse Code.

**Outros:** Pool (hooks-only), Crush (managed-only).

## Segurança

- Verificação de integridade **SHA-256** obrigatória no download da release.
- Substituição de release com retenção da versão anterior até a validação.
- **Rollback automático** se o `init`, o LaunchAgent ou o servidor HTTP falharem.
- O `uninstall` é ownership-aware: não apaga arquivos de configuração de agentes cegamente.

## Estrutura do repositório

```
.
└── install.sh
```

## Licença

Defina a licença do repositório conforme sua preferência (ex.: MIT).
