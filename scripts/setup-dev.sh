#!/usr/bin/env bash
#
# setup-dev.sh — provisiona o ambiente de desenvolvimento do prostaff-events.
#
# O que faz (idempotente — pode rodar quantas vezes quiser):
#   1. Garante que o mise está instalado e no PATH
#   2. Instala Erlang/Elixir nas versões fixadas em .tool-versions
#   3. Instala hex + rebar3
#   4. Baixa deps e compila o projeto
#   5. Cria .env a partir de .env.example (se ainda não existir)
#   6. Imprime os paths dos SDKs para configurar o IntelliJ
#
# Uso:
#   ./scripts/setup-dev.sh
#
set -euo pipefail

# --- localização do repo (funciona de qualquer cwd) -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

info()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m[erro]\033[0m %s\n' "$*" >&2; }

# --- 1. mise ----------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if ! command -v mise >/dev/null 2>&1; then
  err "mise não encontrado."
  err "Instale com:  curl https://mise.run | sh"
  err "Depois adicione ao shell (~/.zshrc):  eval \"\$(mise activate zsh)\""
  exit 1
fi
info "mise: $(mise --version)"

# Erlang pré-compilado dispensa autoconf/openssl do Homebrew (build via source).
mise settings set erlang.compile false 2>/dev/null || true

# --- 2. runtimes (Erlang/Elixir) --------------------------------------------
info "Instalando runtimes de .tool-versions (Erlang + Elixir)..."
mise install

# --- 3. hex + rebar ---------------------------------------------------------
info "Instalando hex + rebar3..."
mise exec -- mix local.hex --force
mise exec -- mix local.rebar --force

# --- 4. deps + compile ------------------------------------------------------
info "Baixando dependências (mix deps.get)..."
mise exec -- mix deps.get
info "Compilando (mix compile)..."
mise exec -- mix compile

# --- 5. .env ----------------------------------------------------------------
if [[ ! -f .env ]]; then
  cp .env.example .env
  warn "Criado .env a partir de .env.example — preencha os segredos antes de subir o servidor."
  warn "Gere o SECRET_KEY_BASE com:  mise exec -- mix phx.gen.secret"
else
  info ".env já existe — mantido."
fi

# --- 6. paths dos SDKs para o IntelliJ --------------------------------------
"$SCRIPT_DIR/print-sdk-paths.sh"

info "Pronto! Ambiente de terminal configurado."
info "Para o IntelliJ, siga: docs/onboarding/dev-environment.md (seção 'IntelliJ')."
