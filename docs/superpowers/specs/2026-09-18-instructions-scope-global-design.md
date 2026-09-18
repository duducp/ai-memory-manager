# Design: `instructions --scope project|global|both`

Data: 2026-09-18
Repositório: `duducp/ai-memory-manager`

## Objetivo

Permitir instalar o bloco de roteamento do ai-memory de forma **global** (arquivos de
instrução do usuário, aplicáveis a todos os projetos), além do comportamento atual
por projeto. Hoje `cmd_instructions` escreve apenas em `AGENTS.md` / `CLAUDE.md` do
diretório alvo, exigindo rodar o comando em cada repositório.

## Decisões aprovadas

- **Abordagem B:** `--target` mantém a semântica atual (arquivos do projeto);
  `--scope` adiciona o eixo de local.
- **Global cobre um conjunto curado de agentes.** Agentes sem arquivo global
  documentado geram aviso e são pulados — nunca inventamos caminhos.
- **Conteúdo oficial.** O bloco gravado nos arquivos globais é o bloco oficial do
  binário (`--compact` por padrão, `--full` opcional). O wrapper não autora um bloco
  global novo; em pt-BR reusa o bloco localizado já existente.
- **Prompt de escopo.** Quando `--scope` é omitido e há terminal, `cmd_instructions`
  pergunta o escopo antes de `--target` e idioma — inclusive quando chamado pelo menu
  interativo (item 6). Sem terminal, assume `project` (compatível com pipe/CI).

## Interface CLI

```
$PROG instructions [--scope project|global|both] [--lang pt-BR|en] \
                   [--target agents|claude|both] [--dir PATH] [--print] [--full]
```

| Flag | Padrão | Semântica |
| --- | --- | --- |
| `--scope` | pergunta com tty; `project` sem tty | `project` = comportamento atual; `global` = arquivos globais; `both` = os dois. Omitido com tty → pergunta; sem tty → `project`. |
| `--target` | inferido | No escopo `project`: `AGENTS.md` / `CLAUDE.md` / ambos. Ignorado no escopo `global` (com aviso se informado). |
| `--dir` | `$PWD` | Diretório do projeto. Ignorado no escopo `global` (com aviso se informado). |
| `--lang` | interativo | `pt-BR` ou `en`. Vale nos dois escopos. |
| `--print` | `false` | Pré-visualiza sem escrever. Vale nos dois escopos. |
| `--full` | `false` | Usa o bloco completo em vez do compacto. Vale nos dois escopos. |

Valor inválido de `--scope` → `die`. `--scope project` permanece 100% compatível com
o comportamento atual. Quando `--scope` é omitido e há terminal, o comando pergunta:

```
Escopo:
  1) Projeto (AGENTS.md / CLAUDE.md)
  2) Global (arquivos globais dos agentes)
  3) Ambos
Escolha [1-3]:
```

O menu interativo (item 6) chama `cmd_instructions` sem argumentos, então passa a
exibir esse prompt naturalmente.

## Resolução do escopo global

Novo mapa curado em `src/agents.sh`, exposto por
`agent_global_instruction_file <agent_name>` (retorna o path ou vazio). Sem arrays
associativos (compatibilidade com bash 3.2 do macOS): usar `case`.

Agentes confirmados:

| Agente | Arquivo global |
| --- | --- |
| `claude-code` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md` |
| `codex` | `$HOME/.codex/AGENTS.md` |
| `opencode` | `$HOME/.config/opencode/AGENTS.md` |
| `gemini-cli` | `$HOME/.gemini/GEMINI.md` |

Candidatos a incluir **somente após verificar a documentação oficial** de cada
agente; enquanto não verificados, caem no balde "sem arquivo global conhecido":

- `devin` → `$HOME/.devin/AGENTS.md`
- `grok` → `${GROK_HOME:-$HOME/.grok}/AGENTS.md`
- `kimi-code` → `${KIMI_CODE_HOME:-$HOME/.kimi-code}/AGENTS.md`
- `kiro-cli` → `${KIRO_HOME:-$HOME/.kiro}/AGENTS.md`
- `command-code` → `$HOME/.commandcode/AGENTS.md`
- `antigravity-cli` → `$HOME/.gemini/antigravity/AGENTS.md`

Os paths usam `expand_home` para respeitar overrides por variável de ambiente.

### Seleção de alvos

1. `agents_detect` (reuso da detecção existente).
2. Para cada agente detectado, resolver `agent_global_instruction_file`.
   - Com path: adicionar à lista de alvos.
   - Sem path: `warn "<nome> não tem arquivo global conhecido; pulando"`.
3. Deduplicar paths idênticos (ex.: `gemini-cli` e `antigravity-cli` podem
   compartilhar árvore sob `~/.gemini`).
4. Se a lista final estiver vazia → `warn` e `return 0` (nada a fazer).

## Fluxo de execução

`cmd_instructions` passa a ter duas passadas independentes:

- **Passada de projeto** (`--scope project` ou `both`): comportamento atual
  (inferência de `--target`, `--dir`, bloco oficial ou pt-BR localizado).
- **Passada global** (`--scope global` ou `both`):
  1. Resolver alvos conforme a seção anterior.
  2. Para cada alvo, chamar o binário oficial:
     `install-instructions --target <path> --skills-scope global`
     (mais `--compact`/`--print` conforme as flags).
  3. Em pt-BR, reusar o fluxo localizado existente (binário oficial primeiro,
     depois o bloco pt-BR entre marcadores), com `--skills-scope global`.
  4. Criar o diretório pai do alvo com `mkdir -p` antes de escrever
     (exceto em `--print`).

`--scope both` executa a passada de projeto e a global em sequência.

## Skills

- Passada de projeto: default do binário (`--skills-scope project`).
- Passada global: `--skills-scope global` (roots documentados: `~/.claude/skills`,
  `~/.agents/skills`, `~/.devin/skills`, `$GROK_HOME/skills`).
- `--scope both` instala skills nos dois escopos.

## Segurança e idempotência

- A escrita continua delegada ao binário oficial, que substitui apenas o bloco entre
  `<!-- ai-memory:start -->` / `<!-- ai-memory:end -->` e mantém backup com timestamp.
- Nunca apagamos arquivos de configuração de agentes.
- O wrapper só cria o arquivo quando o agente foi detectado, evitando arquivos órfãos
  em `$HOME`.

## Conteúdo do bloco

- `en`: bloco oficial do binário, sem alteração.
- `pt-BR`: bloco localizado já existente no wrapper, reusado como está (mesmo texto
  do escopo de projeto).

## Arquivos afetados

- `src/commands.sh` — parsing de `--scope`, prompt de escopo, passadas de projeto/global, `usage` e rótulo do item 6 do `cmd_menu`.
- `src/agents.sh` — mapa curado + `agent_global_instruction_file` + `agents_global_targets`.
- `README.md` — documentar `--scope`, mapa global e exemplos.
- `docs/superpowers/specs/2026-09-18-instructions-scope-global-design.md` — esta spec.

## Fora de escopo

- Arquivos globais para agentes que não têm um (Cursor, Zed, VS Code Copilot,
  Claude Desktop, Swival, Crush, Pool, Muse Code): apenas aviso.
- Alterar o binário upstream do ai-memory.
- Autoria de um bloco global próprio do wrapper.

## Riscos e mitigações

| Risco | Mitigação |
| --- | --- |
| Path global incorreto para um agente | Só incluir no mapa após verificar a doc oficial; caso contrário, aviso + skip. |
| `--scope global` sem agente elegível | `warn` e exit 0, sem tocar em arquivos. |
| Diretório pai inexistente (ex.: `CLAUDE_CONFIG_DIR` custom) | `mkdir -p` antes de escrever. |
| Regressão no escopo de projeto | `--scope` default `project`; código atual preservado. |
| Duplicação de escrita (mesmo path em 2 agentes) | Deduplicar a lista de alvos. |

## Critérios de sucesso

1. `$PROG instructions --scope project` mantém o comportamento de escrita atual. A
   única diferença é o preview pt-BR (`--print`), que passa a incluir o cabeçalho
   `# Would write into: <path>` para ficar consistente com o inglês.
2. `$PROG instructions --scope global --lang en` escreve o bloco oficial nos arquivos
   globais dos agentes detectados e instala skills globais.
3. Agente detectado sem arquivo global gera aviso claro e não cria arquivos.
4. `$PROG instructions --scope both` atualiza projeto e global.
5. `$PROG instructions --scope global --print` não escreve nada.
6. `make check` (shellcheck + `bash -n`) passa.
7. O menu interativo (item 6) pergunta o escopo; sem terminal e sem `--scope`, o
   padrão é `project`.

## Verificação

- `ai-memory install-instructions --target <path absoluto>` já foi validado (exit 0).
- Verificar a documentação oficial dos agentes candidatos antes de adicioná-los.
- Sem suíte automatizada; validar com `bash -n` e `make check`, além de execuções
  manuais de `--scope global --print`.
