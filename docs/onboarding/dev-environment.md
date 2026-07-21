# Onboarding - Development Environment

Guide to get **prostaff-events** running locally and to configure **IntelliJ IDEA**
(Elixir Module SDK). Estimated time: ~10 min.

> **TL;DR**
> ```bash
> ./scripts/setup-dev.sh          # installs runtimes, deps, and compiles
> ./scripts/print-sdk-paths.sh    # prints the paths to paste into IntelliJ
> ```
> Then configure the SDK in IntelliJ (section [3](#3-intellij-elixir-module-sdk)).

---

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| [mise](https://mise.jdx.dev) | recent | version manager (Erlang/Elixir/Ruby) |
| Redis | 7+ | shared with `prostaff-api` |
| IntelliJ IDEA | 2024.1+ | with the **intellij-elixir** plugin |
| Xcode CLT | - | `xcode-select --install` (macOS) |

Erlang/Elixir versions are pinned in [`.tool-versions`](../../.tool-versions) and installed
automatically by mise. Do not install them manually.

### Install mise (if you do not have it yet)

```bash
curl https://mise.run | sh
# add to ~/.zshrc:
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec zsh
```

---

## 2. Runtime setup (terminal)

A single command handles everything (idempotent):

```bash
./scripts/setup-dev.sh
```

It runs:

1. Checks that `mise` is on the PATH
2. `mise install` downloads Erlang and Elixir from `.tool-versions`
3. `mix local.hex` + `mix local.rebar`
4. `mix deps.get` + `mix compile`
5. Creates `.env` from `.env.example` (if missing)
6. Prints the SDK paths for IntelliJ

> **Why precompiled Erlang?**
> The script forces `erlang.compile=false`, so mise downloads the OTP binary instead of
> compiling from source. This avoids having to install `autoconf`, `openssl`, and the like
> via Homebrew.

At the end, fill in the secrets in `.env` (see Section 09 of the README) and generate the
`SECRET_KEY_BASE`:

```bash
mise exec -- mix phx.gen.secret
```

Start the server:

```bash
mise exec -- mix phx.server
curl http://localhost:4000/health   # {"status":"ok",...}
```

---

## 3. IntelliJ - Elixir Module SDK

> Note: the **intellij-elixir** plugin needs **two** SDKs: an **Elixir SDK** that internally
> references an **Erlang SDK**. With mise, Elixir and Erlang live in separate directories, so
> the Erlang SDK is not auto-detected - you must create both manually. This is where most
> people get stuck.

Get the exact paths:

```bash
./scripts/print-sdk-paths.sh
```

### 3.1. Install the plugin (if needed)

In `Settings > Plugins > Marketplace`, search for **"Elixir"** (intellij-elixir), install it,
and restart the IDE.

### 3.2. Create the Erlang SDK (do this FIRST)

1. `Cmd ;` (Project Structure), then `Platform Settings > SDKs`
2. `+`, choose **Erlang SDK**
3. Paste the **Erlang path** printed by the script and confirm.
   It shows up as something like `mise Erlang 27.3.4`.

### 3.3. Create the Elixir SDK and link the Erlang SDK

1. `+`, choose **Elixir SDK**
2. Paste the **Elixir path** and confirm.
3. Select the newly created `Elixir SDK` and, in the **"Internal Erlang SDK"** field, pick the
   `Erlang` SDK from the previous step. The Elixir SDK `classPath` then includes the OTP `ebin`
   directories (`crypto`, `kernel`, `ssl`, and so on).

### 3.4. Assign it as Project + Module SDK

1. `Project Settings > Project`, set **SDK** to the Elixir SDK.
2. `Project Settings > Modules > prostaff_events > Dependencies`, set **Module SDK** to
   `Project SDK` (or the Elixir SDK directly).
3. **Apply**, then **OK**.

### 3.5. Validate

The IDE files should now reflect:

- `prostaff_events.iml` with
  `<orderEntry type="jdk" jdkName="..." jdkType="Elixir SDK" />`
- The Elixir SDK should carry the Erlang ebins in its classPath
  (`.../erlang/<version>/lib/*/ebin`).

To check from the terminal instead (with the IDE closed so you do not lose unsaved changes):

```bash
JDK=~/Library/Application\ Support/JetBrains/IntelliJIdea*/options/jdk.table.xml

grep -c 'erlang/' $JDK          # > 0 means Erlang is linked into the Elixir SDK
grep -E 'orderEntry type="(jdk|inheritedJdk)"' prostaff_events.iml
```

---

## 4. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `:crypto`, `:ets`, `:gen_server` show as *unresolved* | Erlang SDK not linked into the Elixir SDK | Redo section [3.3](#33-create-the-elixir-sdk-and-link-the-erlang-sdk); the "Internal Erlang SDK" field was left empty |
| `Erlang SDK` does not appear in the `+` list | intellij-elixir plugin not installed/active | Section [3.1](#31-install-the-plugin-if-needed) |
| Deps (`Phoenix`, `Redix`) *unresolved* in `import`/`alias` | `deps/` not fetched or IDE out of sync | `./scripts/setup-dev.sh` then `File > Reload All from Disk` |
| `mise install` tries to compile Erlang and fails (autoconf/openssl) | source build | ensure `erlang.compile=false` (the script already does this) and rerun |
| `elixir: command not found` in the terminal | mise not activated in the shell | `eval "$(mise activate zsh)"` in `~/.zshrc` |

---

## 5. Command quick reference

```bash
mise exec -- mix phx.server        # start the server
mise exec -- mix test              # tests
mise exec -- mix format            # format
mise exec -- mix credo --strict    # lint
mise exec -- mix dialyzer          # static analysis
mise exec -- iex -S mix            # REPL with the app loaded
```

> Tip: with mise activated in the shell (`mise activate`), you can drop the `mise exec --`
> prefix and call `mix ...` directly.
