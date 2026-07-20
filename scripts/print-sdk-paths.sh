#!/usr/bin/env bash
#
# print-sdk-paths.sh — imprime os caminhos exatos do Elixir e do Erlang
# (resolvidos pelo mise a partir de .tool-versions) para colar na
# configuração do "Elixir Module SDK" no IntelliJ.
#
# Uso:
#   ./scripts/print-sdk-paths.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v mise >/dev/null 2>&1; then
  echo "mise não encontrado — rode ./scripts/setup-dev.sh primeiro." >&2
  exit 1
fi

ELIXIR_VER="$(mise current elixir 2>/dev/null || true)"
ERLANG_VER="$(mise current erlang 2>/dev/null || true)"
ELIXIR_HOME="$(mise where "elixir@${ELIXIR_VER}" 2>/dev/null || true)"
ERLANG_HOME="$(mise where "erlang@${ERLANG_VER}" 2>/dev/null || true)"

if [[ -z "$ELIXIR_HOME" || -z "$ERLANG_HOME" ]]; then
  echo "Runtimes não instalados — rode ./scripts/setup-dev.sh primeiro." >&2
  exit 1
fi

cat <<EOF

┌──────────────────────────────────────────────────────────────────────┐
│  Paths para configurar o Elixir Module SDK no IntelliJ               │
└──────────────────────────────────────────────────────────────────────┘

  Erlang SDK  (${ERLANG_VER})
    ${ERLANG_HOME}

  Elixir SDK  (${ELIXIR_VER})
    ${ELIXIR_HOME}

  Passo a passo completo: docs/onboarding/dev-environment.md

EOF
