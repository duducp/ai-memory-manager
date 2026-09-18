# Design: installer multi-plataforma para ai-memory (macOS + Linux)

Data: 2026-09-18
Repositório: `duducp/ai-memory-manager`

## Objetivo

Evoluir o instalador `install.sh` (hoje monolítico e exclusivo para macOS) para uma
estrutura modular que:

1. Continue executável via `curl | bash` com um único one-liner.
2. Adicione suporte a Ubuntu/Debian com `systemd --user`.
3. Permita adicionar novos sistemas operacionais criando apenas um arquivo de plataforma.
4. Preserve integralmente o comportamento atual no macOS.

## Decisões aprovadas

- **Escopo Linux:** Ubuntu/Debian com `systemd --user`. Sem suporte a OpenRC/runit nesta iteração.
- **Serviço:** `systemd --user`, sem sudo, equivalente ao LaunchAgent do macOS.
- **Paths Linux:** convenção XDG.
- **Linger:** `loginctl enable-linger "$USER"` tentado automaticamente, best-effort, sem sudo.
- **Arquitetura:** bootstrap fino + árvore modular baixada em runtime.
- **Fora de escopo:** Windows, Linux sem systemd, testes com `bats`.

## Estrutura do repositório

```
install.sh              # bootstrap fino (entry do curl)
src/
  main.sh               # dispatch de comandos + fluxos install/update/uninstall
  common.sh             # log/success/warn/die, cleanup, expand_home, versão, sha256, wait_for_server
  release.sh            # download da release + validação + instalação atômica + rollback
  agents.sh             # tabela de agentes, detecção, health, configure, uninstall
  commands.sh           # status, doctor, logs, instructions, usage
  platform/
    macos.sh            # paths, launchd, checks macOS
    linux.sh            # paths, systemd --user, checks Linux
```

O arquivo `install.sh` permanece como único ponto de entrada público. Nenhum outro
arquivo do repo precisa ser baixado diretamente pelo usuário.

## Bootstrap (`install.sh`)

Responsabilidades:

1. `set -euo pipefail`.
2. Detectar o SO com `uname -s`:
   - `Darwin` → plataforma `macos`
   - `Linux` → plataforma `linux`
   - qualquer outro → erro claro.
3. Resolver o modo de execução:
   - **Checkout local:** se `src/main.sh` existir ao lado do script (resolvido via
     `BASH_SOURCE`), usa os arquivos locais. Facilita desenvolvimento e testes.
   - **Pipe (`curl | bash`):** baixa o snapshot do repositório em
     `https://codeload.github.com/duducp/ai-memory-manager/tar.gz/refs/heads/${REF}`
     para um diretório temporário, extrai e usa `src/main.sh` de lá.
4. `REF` padrão é `main`, sobrescrevível pela variável de ambiente `AI_MEMORY_MANAGER_REF`.
5. Encaminha `"$@"` para `src/main.sh`.
6. Registra trap de limpeza para remover o diretório temporário.

O bootstrap não contém lógica de instalação, de plataforma ou de agentes.

## Contrato de plataforma

Cada `src/platform/<os>.sh` implementa as mesmas funções. O restante do código
nunca inspeciona o SO diretamente.

| Função | Responsabilidade |
| --- | --- |
| `platform_name` | Nome legível (`macos`, `linux`). |
| `platform_init_paths` | Define `INSTALL_ROOT`, `BIN_DIR`, `BINARY`, `BIN_LINK`, `DATA_DIR`, `CONFIG_DIR`, `LOG_DIR`, `LABEL`, `SERVER_HOST`, `SERVER_PORT`, `SERVER_URL`, `MCP_URL`. |
| `platform_require` | Valida dependências obrigatórias do SO e aborta com mensagem clara. |
| `platform_asset_name` | Retorna o nome do asset da release para o SO/arch atual (ex.: `ai-memory-linux-x86_64.tar.gz`). |
| `platform_service_install` | Escreve e carrega/ativa o serviço. |
| `platform_service_uninstall` | Para e remove o serviço. |
| `platform_service_is_active` | Retorna 0 se o serviço está ativo. |
| `platform_service_status` | Imprime `RUNNING` / `NOT RUNNING` (usado pelo `status`). |
| `platform_extra_doctor_checks` | Checks adicionais no `doctor` (default: no-op). |

Funções comuns ficam em `src/common.sh` e não são sobrescritas por plataforma:
logging, `cleanup`, `expand_home`, `current_version`, `detect_arch`, `sha256_of`,
`require_cmd` e `wait_for_server`.

### Detecção de arquitetura

`detect_arch` mapeia `uname -m`:

- `arm64` / `aarch64` → `aarch64`
- `x86_64` / `amd64` → `x86_64`

Qualquer outra arquitetura aborta com erro.

### Checksum

`sha256_of` usa `shasum -a 256` quando disponível e cai para `sha256sum` caso
contrário. `platform_require` garante que ao menos um dos dois existe.

## Plataforma macOS (`src/platform/macos.sh`)

Comportamento idêntico ao instalador atual:

- `INSTALL_ROOT`: `~/Applications/ai-memory`
- `BIN_DIR`: `~/.local/bin`, link em `~/.local/bin/ai-memory`
- `DATA_DIR` / `CONFIG_DIR`: `~/Library/Application Support/ai-memory`
- `LOG_DIR`: `~/Library/Logs/ai-memory`
- Serviço: LaunchAgent `~/Library/LaunchAgents/com.ai-memory.server.plist`,
  label `com.ai-memory.server`, com `RunAtLoad` e `KeepAlive`.
- `platform_require`: `curl`, `tar`, `shasum`, `launchctl`, `plutil` e `python3`
  (para `instructions`).
- `platform_service_*` usa `launchctl bootout/bootstrap/enable/kickstart/print`.
- `platform_extra_doctor_checks`: valida `macOS`, `launchctl`.

## Plataforma Linux (`src/platform/linux.sh`)

- `INSTALL_ROOT`: `~/.local/share/ai-memory`
- `BIN_DIR`: `~/.local/bin`, link em `~/.local/bin/ai-memory`
- `DATA_DIR`: `~/.local/share/ai-memory`
- `CONFIG_DIR`: `~/.config/ai-memory`
- `LOG_DIR`: `~/.local/state/ai-memory`
- Serviço: unit de usuário em `~/.config/systemd/user/ai-memory.service`.
- `platform_require`: `curl`, `tar`, `systemctl`, `loginctl`, `python3` e um
  verificador SHA-256 (`sha256sum` ou `shasum`).
- `platform_asset_name`: `ai-memory-linux-${ARCH}.tar.gz`.

### Unit systemd

```ini
[Unit]
Description=ai-memory MCP server
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/ai-memory serve --transport http --bind 127.0.0.1:49374
WorkingDirectory=%h/.local/share/ai-memory
Restart=always
RestartSec=2
StandardOutput=append:%h/.local/state/ai-memory/server.log
StandardError=append:%h/.local/state/ai-memory/server.error.log

[Install]
WantedBy=default.target
```

`platform_service_install` executa:

1. `systemctl --user daemon-reload`
2. `systemctl --user enable --now ai-memory.service`
3. `loginctl enable-linger "$USER"` (best-effort; avisa se falhar, não aborta)

`platform_service_uninstall` executa `systemctl --user disable --now ai-memory.service`
e remove o arquivo do unit, seguido de `daemon-reload`.

`platform_service_is_active` usa `systemctl --user is-active --quiet ai-memory.service`.

`StandardOutput=append:` exige systemd 240+ (presente no Ubuntu 20.04+/Debian 12+),
garantindo paridade com o comando `logs`, que lê arquivos.

## Fluxos de comando (`src/main.sh`)

Comandos mantidos: `install`, `update`, `status`, `doctor`, `logs`, `instructions`,
`uninstall`, `help`.

### `install`

1. `platform_require`, `detect_arch`.
2. Se o binário já existe: avisa e encerra (mesmo comportamento atual).
3. `release_download` baixa o asset de `platform_asset_name` e valida SHA-256.
4. `release_install` faz extração e substituição atômica, retendo a release anterior.
5. `init_memory` (`ai-memory init`).
6. `platform_service_install`.
7. `wait_for_server`; em falha, desinstala o serviço, restaura a release anterior e aborta.
8. `agents_configure`.
9. Remove a release antiga retida.

### `update`

Fluxo atual preservado: baixa, valida, para o serviço, ativa a nova release, roda
`init`, reativa o serviço e valida o HTTP. Qualquer falha restaura a release anterior
e reativa o serviço.

### `uninstall`

- Sem `--purge`: remove serviço, integrações, link e release; preserva dados.
- Com `--purge`: remove também `DATA_DIR`.
- A limpeza de integrações continua delegada ao `ai-memory uninstall --apply`
  (ownership-aware); nunca apaga configs de agentes às cegas.

## Agentes (`src/agents.sh`)

- Tabela `AGENTS` e lógica de detecção/health movidas sem mudança de semântica.
- A detecção usa primeiro o executável, depois os diretórios de configuração.
- `configure`/`uninstall` continuam delegando a `install-mcp`/`install-hooks`/`uninstall`
  do binário oficial.
- `claude-desktop` permanece na tabela; no Linux simplesmente não é detectado.

## CI e documentação

- `.github/workflows/lint.yml`: roda `shellcheck` em `install.sh` e `src/**/*.sh`,
  além de `bash -n` em todos os arquivos.
- `README.md` atualizado com:
  - one-liners de instalação para macOS e Linux;
  - tabela de paths por SO;
  - variável `AI_MEMORY_MANAGER_REF`;
  - estrutura do repositório;
  - nota sobre `bash -s <comando>` em execução via pipe.

## Riscos e mitigações

| Risco | Mitigação |
| --- | --- |
| Download extra do snapshot no modo pipe | Um único request de tarball; reaproveita `curl` já exigido. Modo checkout local evita download em dev. |
| `StandardOutput=append:` indisponível em systemd antigo | Escopo declarado é Ubuntu 22.04+/Debian 12+; `platform_require` pode validar a versão do systemd. |
| Regressão no macOS | Lógica movida sem alteração semântica; `shellcheck` no CI. |
| Linger negado por política | Best-effort, apenas aviso; serviço continua funcional na sessão ativa. |

## Critérios de sucesso

1. `curl -fsSL .../install.sh | bash -s install` funciona em macOS (paridade com hoje)
   e em Ubuntu 22.04+/Debian 12+.
2. `status`, `doctor`, `logs`, `update` e `uninstall` funcionam nos dois SOs.
3. Adicionar um novo SO exige apenas um arquivo `src/platform/<os>.sh` que implemente
   o contrato, sem tocar em `common.sh`, `release.sh` ou `agents.sh`.
4. `shellcheck` passa sem erros no CI.
