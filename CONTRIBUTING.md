# Contribuindo

Obrigado pelo interesse em contribuir com o `ai-memory-manager`. Este guia cobre o
essencial; as convenções detalhadas de código estão em [`AGENTS.md`](AGENTS.md) e o
design da arquitetura em
[`docs/superpowers/specs/2026-09-18-multi-platform-installer-design.md`](docs/superpowers/specs/2026-09-18-multi-platform-installer-design.md).

## Requisitos de desenvolvimento

- Bash (`set -euo pipefail` em todos os arquivos)
- `shellcheck` (obrigatório)
- `curl`, `tar`, `python3`
- macOS ou Linux

Instale o `shellcheck`:

```bash
brew install shellcheck          # macOS
sudo apt-get install shellcheck  # Ubuntu/Debian
```

## Rodando localmente (sem instalar nada)

```bash
git clone https://github.com/duducp/ai-memory-manager.git
cd ai-memory-manager

make check            # shellcheck + bash -n
bash install.sh help
bash install.sh status
bash install.sh doctor
bash install.sh       # abre o menu interativo
```

O `install.sh` detecta automaticamente que está em um checkout local e usa os módulos
de `src/` diretamente, sem baixar nada.

> `install`, `update` e `uninstall` modificam a máquina. Teste essas operações em uma
> VM, container ou usuário descartável.

## Verificação obrigatória

Não há suíte de testes automatizados (`bats` está fora de escopo). Antes de abrir um PR:

```bash
make check
```

Isso roda `shellcheck` e `bash -n` em `install.sh`, `src/*.sh` e `src/platform/*.sh`.
O mesmo comando roda no CI (`.github/workflows/lint.yml`).

Para mudanças de comportamento, inclua também um smoke test manual no PR:

```bash
bash install.sh help
bash install.sh status
bash install.sh doctor
```

## Estrutura

```
install.sh              # bootstrap fino (entry do curl); não contém lógica de instalação
src/
  main.sh               # dispatch de comandos + fluxos install/update/uninstall
  common.sh             # logging, helpers, sha256, wait_for_server, prompt
  release.sh            # download, validação, instalação atômica, rollback
  agents.sh             # tabela de agentes, detecção, health, configure, uninstall
  commands.sh           # status, doctor, logs, instructions, menu
  platform/
    macos.sh            # paths, launchd, checks
    linux.sh            # paths, systemd --user, checks
```

`install.sh` e `src/main.sh` decidem **o quê**; os módulos implementam **como**;
`src/platform/*.sh` isolam **onde** (caminhos e serviço).

## Adicionando suporte a um novo sistema operacional

1. Crie `src/platform/<os>.sh` implementando o contrato descrito em `AGENTS.md`
   (`platform_init_paths`, `platform_require`, `platform_asset_name`,
   `platform_service_*`, `platform_extra_doctor_checks`).
2. Registre a detecção em `install.sh` (mapeamento `uname -s` → plataforma).
3. Garanta que `platform_asset_name` corresponde ao asset publicado pela release oficial
   (`ai-memory-<os>-<arch>.tar.gz`).
4. Não altere `common.sh`, `release.sh` nem `agents.sh` — se precisar, o contrato está
   incompleto e deve ser discutido antes.
5. Atualize o `README.md` com o one-liner e a tabela de paths.
6. Rode `make check`.

## Convenções

- Mensagens voltadas ao usuário em **português**.
- Funções de plataforma usam o prefixo `platform_`; as demais, o prefixo do módulo
  (`release_`, `agents_`, `cmd_`).
- Nunca inspecione `uname` fora do bootstrap (`install.sh`) e de `src/platform/*.sh`.
- Não adicione dependências novas sem necessidade justificada.
- Evite comentários óbvios; comente apenas decisões não triviais.
- O `.shellcheckrc` desabilita apenas códigos que são falsos positivos estruturais da
  arquitetura modular (`SC2034`, `SC2120`, `SC2119`). Não desabilite outros.

## Fluxo de contribuição

1. Crie uma branch a partir de `main` (ex.: `feat/linux-arm`, `fix/rollback`).
2. Faça as mudanças seguindo as convenções acima.
3. Rode `make check` e os smoke tests relevantes.
4. Escreva commits no padrão [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`).
5. Abra um Pull Request descrevendo a motivação, o que mudou e como você testou.

O CI roda `shellcheck` e `bash -n` automaticamente em pushes e PRs.

## Reportando bugs

Inclua no issue:

- Sistema operacional e arquitetura (`uname -a`);
- comando executado e a saída completa;
- resultado de `bash install.sh doctor` e `bash install.sh status`;
- logs relevantes (`bash install.sh logs --tail 100`).

## Segurança

- A validação de integridade **SHA-256 é obrigatória**; nunca instale sem conferir.
- Toda falha em `init`, no serviço ou no HTTP deve acionar **rollback automático**.
- A limpeza de integrações de agentes é ownership-aware: delegue ao
  `ai-memory uninstall --apply`; nunca apague configs de agentes às cegas.
- Nunca registre segredos ou tokens em logs.
