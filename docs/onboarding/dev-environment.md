# Onboarding — Ambiente de Desenvolvimento

Guia para deixar o **prostaff-events** rodando localmente e configurar o
**IntelliJ IDEA** (Elixir Module SDK). Estimativa: ~10 min.

> **TL;DR**
> ```bash
> ./scripts/setup-dev.sh          # instala runtimes, deps e compila
> ./scripts/print-sdk-paths.sh    # mostra os paths p/ colar no IntelliJ
> ```
> Depois configure o SDK no IntelliJ (seção [3](#3--intellij--elixir-module-sdk)).

---

## 1 · Pré-requisitos

| Ferramenta | Versão | Observação |
|------------|--------|------------|
| [mise](https://mise.jdx.dev) | recente | gerenciador de versões (Erlang/Elixir/Ruby) |
| Redis | 7+ | compartilhado com a `prostaff-api` |
| IntelliJ IDEA | 2024.1+ | com o plugin **intellij-elixir** |
| Xcode CLT | — | `xcode-select --install` (macOS) |

As versões de Erlang/Elixir são fixadas em [`.tool-versions`](../../.tool-versions)
e instaladas automaticamente pelo mise — **não instale manualmente**.

### Instalar o mise (se ainda não tiver)

```bash
curl https://mise.run | sh
# adicione ao ~/.zshrc:
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec zsh
```

---

## 2 · Setup do runtime (terminal)

Um comando resolve tudo (idempotente):

```bash
./scripts/setup-dev.sh
```

Ele executa:

1. Verifica o `mise` no PATH
2. `mise install` — baixa **Erlang** e **Elixir** de `.tool-versions`
3. `mix local.hex` + `mix local.rebar`
4. `mix deps.get` + `mix compile`
5. Cria `.env` a partir de `.env.example` (se não existir)
6. Imprime os paths dos SDKs para o IntelliJ

> **Por que Erlang pré-compilado?**
> O script força `erlang.compile=false`, então o mise baixa o binário do OTP
> em vez de compilar do source. Isso evita ter que instalar `autoconf`,
> `openssl` e afins via Homebrew.

Ao final, preencha os segredos no `.env` (veja a Seção 09 do README) e gere o
`SECRET_KEY_BASE`:

```bash
mise exec -- mix phx.gen.secret
```

Suba o servidor:

```bash
mise exec -- mix phx.server
curl http://localhost:4000/health   # {"status":"ok",...}
```

---

## 3 · IntelliJ — Elixir Module SDK

> ⚠️ O plugin **intellij-elixir** precisa de **dois** SDKs: um **Elixir SDK**
> que referencia internamente um **Erlang SDK**. Com o mise, Elixir e Erlang
> ficam em pastas **separadas**, então o Erlang **não** é auto-detectado —
> você precisa criar os dois manualmente. É aqui que a maioria trava.

Pegue os paths exatos:

```bash
./scripts/print-sdk-paths.sh
```

### 3.1 · Instalar o plugin (se necessário)

`Settings → Plugins → Marketplace` → busque **"Elixir"** (intellij-elixir) →
Install → reinicie o IDE.

### 3.2 · Criar o Erlang SDK  ← faça este PRIMEIRO

1. `⌘ ;` (Project Structure) → `Platform Settings → SDKs`
2. `+` → **Erlang SDK**
3. Cole o **path do Erlang** impresso pelo script → OK
   → aparece algo como `mise Erlang 27.3.4`

### 3.3 · Criar o Elixir SDK e linkar o Erlang

1. `+` → **Elixir SDK**
2. Cole o **path do Elixir** → OK
3. Selecione o `Elixir SDK` recém-criado e, no campo
   **"Internal Erlang SDK"**, escolha o `Erlang` do passo anterior
   → o `classPath` do Elixir SDK passa a incluir os `ebin` do OTP
   (`crypto`, `kernel`, `ssl`, …)

### 3.4 · Atribuir como Project + Module SDK

1. `Project Settings → Project` → **SDK** = o Elixir SDK
2. `Project Settings → Modules → prostaff_events → Dependencies`
   → **Module SDK** = `Project SDK` (ou o Elixir SDK direto)
3. **Apply → OK**

### 3.5 · Validar

Ao final, os arquivos do IDE devem refletir:

- `prostaff_events.iml` →
  `<orderEntry type="jdk" jdkName="..." jdkType="Elixir SDK" />`
- O Elixir SDK deve ter **os ebins do Erlang** no classPath
  (`.../erlang/<versão>/lib/*/ebin`).

Se preferir checar por terminal (com o IDE **fechado** para não perder
alterações não salvas):

```bash
JDK=~/Library/Application\ Support/JetBrains/IntelliJIdea*/options/jdk.table.xml

grep -c 'erlang/' $JDK          # > 0  → Erlang linkado no Elixir SDK
grep -E 'orderEntry type="(jdk|inheritedJdk)"' prostaff_events.iml
```

---

## 4 · Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| `:crypto`, `:ets`, `:gen_server` aparecem como *unresolved* | Erlang SDK não linkado no Elixir SDK | Refaça a seção [3.3](#33--criar-o-elixir-sdk-e-linkar-o-erlang) — o campo "Internal Erlang SDK" ficou vazio |
| `+ → Erlang SDK` não aparece na lista | plugin intellij-elixir não instalado/ativo | Seção [3.1](#31--instalar-o-plugin-se-necessário) |
| Deps (`Phoenix`, `Redix`) *unresolved* nos `import`/`alias` | `deps/` não baixado ou IDE dessincronizado | `./scripts/setup-dev.sh` e depois `File → Reload All from Disk` |
| `mise install` tenta compilar Erlang e falha (autoconf/openssl) | build via source | garanta `erlang.compile=false` (o script já faz) e rode de novo |
| `elixir: command not found` no terminal | mise não ativado no shell | `eval "$(mise activate zsh)"` no `~/.zshrc` |

---

## 5 · Referência rápida de comandos

```bash
mise exec -- mix phx.server        # sobe o servidor
mise exec -- mix test              # testes
mise exec -- mix format            # formata
mise exec -- mix credo --strict    # lint
mise exec -- mix dialyzer          # análise estática
mise exec -- iex -S mix            # REPL com o app carregado
```

> Dica: com o mise ativado no shell (`mise activate`), você pode omitir o
> `mise exec --` e chamar `mix ...` direto.
