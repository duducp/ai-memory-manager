# AGENTS.md

Guia para agentes de IA (e humanos) que trabalham neste repositório.

## Visão geral

`ai-memory-manager` é um instalador multi-plataforma para o
[ai-memory](https://github.com/akitaonrails/ai-memory). Ele baixa a release oficial,
valida o SHA-256, instala o binário, registra o servidor HTTP como serviço de usuário
(launchd no macOS, `systemd --user` no Linux) e conecta automaticamente os agentes de
IA detectados (MCP + hooks).

O ponto de entrada público é sempre `install.sh`, executável via `curl | bash`.

## Estrutura do repositório

```
install.sh              # bootstrap fino (entry do curl); não contém lógica de instalação
src/
  main.sh               # dispatch de comandos + fluxos install/update/uninstall
  common.sh             # logging, cleanup, expand_home, versão, sha256, wait_for_server
  release.sh            # download da release, validação, instalação atômica, rollback
  agents.sh             # tabela de agentes, detecção, health, configure, uninstall
  commands.sh           # status, doctor, logs, instructions, usage
  platform/
    macos.sh            # paths, launchd, checks macOS
    linux.sh            # paths, systemd --user, checks Linux
docs/superpowers/specs/ # specs de design
```

Regra de ouro: `install.sh` e `src/main.sh` decidem **o quê**; os módulos implementam
**como**; `src/platform/*.sh` isolam **onde** (caminhos e serviço).

## Execução e verificação

Não há suíte de testes automatizados (bats está fora de escopo). Use:

```bash
# Lint obrigatório antes de concluir qualquer mudança
shellcheck install.sh src/**/*.sh

# Checagem de sintaxe (roda mesmo sem shellcheck instalado)
for f in install.sh src/*.sh src/platform/*.sh; do bash -n "$f"; done

# Ajuda sem instalar nada (modo checkout local)
bash install.sh help

# Diagnóstico em uma máquina já instalada
bash install.sh doctor
bash install.sh status
```

Sempre rode `shellcheck` e `bash -n` antes de considerar uma tarefa concluída.

## Convenções de código

- Bash puro, com `set -euo pipefail` em **todos** os arquivos.
- Mensagens voltadas ao usuário em **português**.
- Funções de plataforma usam o prefixo `platform_`; funções comuns usam o prefixo do
  módulo (`release_`, `agents_`, etc.).
- Nunca inspecione `uname` fora do bootstrap (`install.sh`) e de `src/platform/*.sh`.
- Dependências permitidas: `curl`, `tar`, `launchctl`/`systemctl`, `python3` e um
  verificador SHA-256 (`shasum` ou `sha256sum`). Não adicione dependências novas sem
  necessidade justificada.
- Evite comentários óbvios; comente apenas decisões não triviais.

## Contrato de plataforma

Todo `src/platform/<os>.sh` deve implementar as funções abaixo. O restante do código
depende apenas deste contrato.

| Função | Responsabilidade |
| --- | --- |
| `platform_name` | Nome legível (`macos`, `linux`). |
| `platform_init_paths` | Define `INSTALL_ROOT`, `BIN_DIR`, `BINARY`, `BIN_LINK`, `DATA_DIR`, `CONFIG_DIR`, `LOG_DIR`, `LABEL`, `SERVER_HOST`, `SERVER_PORT`, `SERVER_URL`, `MCP_URL`. |
| `platform_require` | Valida dependências obrigatórias do SO e aborta com mensagem clara. |
| `platform_asset_name` | Nome do asset da release para o SO/arch atual. |
| `platform_service_install` | Escreve e ativa o serviço. |
| `platform_service_uninstall` | Para e remove o serviço. |
| `platform_service_is_active` | Retorna 0 se o serviço está ativo. |
| `platform_service_status` | Imprime `RUNNING` / `NOT RUNNING`. |
| `platform_extra_doctor_checks` | Checks adicionais do `doctor` (default: no-op). |

## Como adicionar um novo sistema operacional

1. Crie `src/platform/<os>.sh` implementando o contrato completo.
2. Registre a detecção em `install.sh` (mapeamento `uname -s` → plataforma).
3. Garanta que `platform_asset_name` corresponde ao asset publicado pela release
   oficial do ai-memory (`ai-memory-<os>-<arch>.tar.gz`).
4. Não altere `common.sh`, `release.sh` nem `agents.sh` — se precisar, o contrato está
   incompleto e deve ser discutido antes.
5. Atualize o `README.md` com o one-liner e a tabela de paths do novo SO.
6. Rode `shellcheck` e `bash -n`.

## Segurança

- A validação de integridade **SHA-256 é obrigatória**; nunca instale sem conferir.
- A substituição de release deve ser atômica e reter a versão anterior até a validação
  do servidor.
- Qualquer falha em `init`, no serviço ou no HTTP deve acionar **rollback automático**.
- A limpeza de integrações de agentes é ownership-aware: delegue ao
  `ai-memory uninstall --apply`. Nunca apague arquivos de configuração de agentes às
  cegas.
- Nunca registre segredos ou tokens em logs.

## Commits

- Mensagens no padrão Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`).
- Não faça commit/push sem pedido explícito.
- Mudanças de design devem atualizar a spec correspondente em `docs/superpowers/specs/`.

## Referências

- Design multi-plataforma: `docs/superpowers/specs/2026-09-18-multi-platform-installer-design.md`
- Projeto upstream: https://github.com/akitaonrails/ai-memory
