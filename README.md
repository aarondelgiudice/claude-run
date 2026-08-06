# claude-local-sandbox

Run Claude Code against Anthropic's cloud API or a local Ollama model, either
directly or inside a Docker container for filesystem isolation.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for `--sandbox`)
- [Ollama](https://ollama.com/) running locally (for `--api local`)
- [Claude Code](https://claude.com/claude-code) installed (`npm install -g @anthropic-ai/claude-code`)

## Setup (new machine)

```bash
git clone <this-repo> claude-local-sandbox
cd claude-local-sandbox
./setup.sh
```

`setup.sh` is idempotent (safe to re-run) and handles:
- Checking Docker/Claude Code are installed and Docker is running
- Installing Ollama via Homebrew if it's missing (or pointing you to the
  manual installer if Homebrew isn't available)
- Setting Ollama's performance env vars via `launchctl setenv`
  (`OLLAMA_FLASH_ATTENTION`, `OLLAMA_KV_CACHE_TYPE`, `OLLAMA_KEEP_ALIVE`) and
  restarting Ollama so they take effect — these persist across reboots once
  set, but need to be set again on a machine that's never had them
- Detecting a host UID mismatch against the Dockerfile and offering to fix it
- Building the `claude-local-sandbox` image (**this step is required on every
  machine** — Docker images aren't portable through git, only the Dockerfile is;
  each machine builds its own image from it)
- Adding a `source` line to `~/.zshrc` (only once — checks first)
- Optionally pulling the default `qwen3-coder` Ollama model

After it finishes: `source ~/.zshrc` (or open a new terminal), then try
`claude --api local`.

### Manual setup (if you'd rather not run the script)

1. Install Ollama: `brew install --cask ollama`, or download from
   [ollama.com](https://ollama.com/download).
2. Set performance env vars and restart Ollama so they take effect:
   ```bash
   launchctl setenv OLLAMA_FLASH_ATTENTION 1
   launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0
   launchctl setenv OLLAMA_KEEP_ALIVE 60m
   osascript -e 'quit app "Ollama"'
   open -a Ollama
   ```
3. Check your host UID (`id -u`); if it's not `501`, edit the `useradd -u 501`
   line in `Dockerfile` to match.
4. `docker build -t claude-local-sandbox .`
5. Add `source /path/to/claude-local-sandbox.zsh` to `~/.zshrc`, then
   `source ~/.zshrc`.
6. `ollama pull qwen3-coder`

## Usage

```bash
claude                                              # cloud (Anthropic)
claude --sandbox                                    # cloud, Docker-isolated, bypass permissions
claude --api local                                  # Ollama (qwen3-coder), --bare + --exclude-dynamic-system-prompt-sections
claude --api local --model qwen2.5-coder:14b         # Ollama, different model
claude --api local --sandbox                        # Ollama, Docker-isolated, --bare + --exclude-dynamic-system-prompt-sections + bypass permissions
claude --api deepseek                               # external API (DeepSeek), needs $DEEPSEEK_API_KEY
claude --api deepseek --sandbox                     # external API, Docker-isolated, bypass permissions
```

`--api <backend>` picks where requests go; `--sandbox` is orthogonal and adds
Docker isolation to any of them. All native `claude` flags (`--resume`,
`--permission-mode <mode>`, etc.) pass through normally, e.g.:
```bash
claude --sandbox --resume
claude --api local --permission-mode plan
```

### Flags and defaults

| Flag | Effect | Default |
|---|---|---|
| `--api <backend>` | Pick where requests go: `local` (Ollama) or a hosted provider like `deepseek` — see below | cloud (Anthropic) |
| `--sandbox` | Run inside the `claude-local-sandbox` Docker container | off |
| `--model <name>` | Model to use (sets the Ollama model under `--api local`; overrides the primary model under a hosted `--api`) | `qwen3-coder` |
| `--no-bare` | Disable `--bare` (skips tool calls to run faster) — see below | n/a |
| `--no-exclude-dynamic-system-prompt-sections` | Disable `--exclude-dynamic-system-prompt-sections` (drops dynamic prompt sections) — see below | n/a |
| `--no-skip-permissions` | Disable `--dangerously-skip-permissions` — see below | n/a |

**`--bare` (Claude Code's minimal-tools mode) is on by default whenever
`--api local` is used** (`claude --api local` and `claude --api local --sandbox`),
since local models are much slower once Claude Code's full tool schema is loaded.
Opt out with `--no-bare` if you want tools available on a local model:
```bash
claude --api local --no-bare
claude --api local --sandbox --no-bare
```

**`--exclude-dynamic-system-prompt-sections` is on by default whenever
`--api local` is used** (`claude --api local` and `claude --api local --sandbox`),
dropping the dynamic (per-run) sections of Claude Code's system prompt to keep
the prompt smaller for local models. Opt out with
`--no-exclude-dynamic-system-prompt-sections`:
```bash
claude --api local --no-exclude-dynamic-system-prompt-sections
claude --api local --sandbox --no-exclude-dynamic-system-prompt-sections
```

**`--dangerously-skip-permissions` is on by default whenever `--sandbox` is
used** (`claude --sandbox` and `claude --api <backend> --sandbox`), since the
Docker container provides a real filesystem boundary that makes bypass mode
reasonable there. It is **not** applied to `--api local` without `--sandbox` (no
container boundary, so normal permission prompting still applies). Opt out with
`--no-skip-permissions`:
```bash
claude --sandbox --no-skip-permissions
claude --api local --sandbox --no-skip-permissions
```

**Default permission mode / plan mode:** use the native `--permission-mode`
flag (accepts `default`, `acceptEdits`, `plan`, `bypassPermissions`), e.g.
`claude --api local --permission-mode plan`. Note this may conflict with
`--dangerously-skip-permissions` if both are active in a sandboxed mode —
skip-permissions takes precedence when both are present.

### External APIs (hosted `--api` backends)

Besides `local` (Ollama, covered above), `--api` can route Claude Code to a
hosted Anthropic-compatible API. Each backend's environment is set inline per
invocation and never exported, so backends never leak into each other or into a
later plain `claude`.

Known hosted provider: **`deepseek`**. Set your key first (get it from the
[DeepSeek Platform](https://platform.deepseek.com/)):
```bash
export DEEPSEEK_API_KEY=sk-...   # in ~/.zshrc or a secrets file
```
Then:
```bash
claude --api deepseek                          # default model deepseek-v4-pro
claude --api deepseek --model deepseek-v4-flash # override the primary model
claude --api deepseek --sandbox                # same, Docker-isolated (bypass permissions on)
```
The wrapper errors if `$DEEPSEEK_API_KEY` is unset.

`--bare` and `--exclude-dynamic-system-prompt-sections` apply only to
`--api local` (they are local-model tweaks), not to hosted providers.
`--dangerously-skip-permissions` still follows the usual rule: on by default
only when `--sandbox` is present.

**Adding a hosted provider:** edit the `case "$api_provider"` block in
`claude-local-sandbox.zsh`. Each provider sets a base URL, the name of the env
var holding its key, and its model names.

### First run of `--sandbox`

The first time you run `claude --sandbox` on a machine, it will prompt you to
log in (the container can't access credentials stored in macOS Keychain, only
what's in `~/.claude.json` on disk). Complete the login flow once; subsequent
runs from directories where you've already authenticated should not require
re-login within the same container's lifetime, but note this setup uses
`--rm` (ephemeral containers), so **you may need to log in again per fresh
container** depending on where your session state actually persists. See the
"Known limitations" section below.

## Known limitations

- **`--sandbox` UID coupling:** the Docker image's `agent` user is built with
  a hardcoded UID (default `501`) to match typical macOS single-user setups.
  If you're on a machine with a different primary UID, update the Dockerfile
  before building, or `~/.claude`/`~/.claude.json` mounts may show ownership
  mismatches.
- **Login persistence:** full session credentials for `--sandbox` mode may not
  be fully captured by `~/.claude.json` alone (some auth state may live in
  macOS Keychain, which isn't mountable into a Linux container). If you hit
  repeated login prompts, consider running a **named, non-`--rm` container**
  for `--sandbox` mode instead, so login state persists across runs:
  ```bash
  docker run -it --name claude-sandbox-persistent -v "$(pwd)":/work claude-local-sandbox
  # later:
  docker start -ai claude-sandbox-persistent
  ```
  Trade-off: a persistent named container is tied to the directory it was
  first created in.
- **`--model` is meaningful with `--api`.** Under `--api local` it picks the
  Ollama model; under a hosted `--api` it overrides the provider's primary
  model. Passing it in plain cloud or `--sandbox`-only mode is silently ignored.
- **`--bare` and `--dangerously-skip-permissions` have different defaults per
  mode** — see the flags table under Usage. When unsure what a given invocation
  will actually run, read the `case "$api_provider"` block in the function
  source.
