# claude-local-sandbox

Run Claude Code against Anthropic's cloud API or a local Ollama model, either
directly or inside a Docker container for filesystem isolation.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for `--sandbox` modes)
- [Ollama](https://ollama.com/) running locally (for `--local` modes)
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
`claude --local`.

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
claude                                              # normal, cloud
claude --sandbox                                    # cloud model, Docker-isolated, bypass permissions
claude --local                                      # local model (qwen3-coder), --bare + --exclude-dynamic-system-prompt-sections
claude --local --model qwen2.5-coder:14b             # local model, different model
claude --local --sandbox                            # local model, Docker-isolated, --bare + --exclude-dynamic-system-prompt-sections + bypass permissions
```

All native `claude` flags (`--resume`, `--permission-mode <mode>`, etc.) pass
through normally, e.g.:
```bash
claude --sandbox --resume
claude --local --permission-mode plan
```

### Flags and defaults

| Flag | Effect | Default |
|---|---|---|
| `--local` | Route to a local Ollama model instead of the cloud API | off |
| `--sandbox` | Run inside the `claude-local-sandbox` Docker container | off |
| `--model <name>` | Model to use (only meaningful with `--local`) | `qwen3-coder` |
| `--no-bare` | Disable `--bare` (skips tool calls to run faster) — see below | n/a |
| `--no-exclude-dynamic-system-prompt-sections` | Disable `--exclude-dynamic-system-prompt-sections` (drops dynamic prompt sections) — see below | n/a |
| `--no-skip-permissions` | Disable `--dangerously-skip-permissions` — see below | n/a |

**`--bare` (Claude Code's minimal-tools mode) is on by default whenever
`--local` is used** (`claude --local` and `claude --local --sandbox`), since
local models are much slower once Claude Code's full tool schema is loaded.
Opt out with `--no-bare` if you want tools available on a local model:
```bash
claude --local --no-bare
claude --local --sandbox --no-bare
```

**`--exclude-dynamic-system-prompt-sections` is on by default whenever
`--local` is used** (`claude --local` and `claude --local --sandbox`), dropping
the dynamic (per-run) sections of Claude Code's system prompt to keep the
prompt smaller for local models. Opt out with
`--no-exclude-dynamic-system-prompt-sections`:
```bash
claude --local --no-exclude-dynamic-system-prompt-sections
claude --local --sandbox --no-exclude-dynamic-system-prompt-sections
```

**`--dangerously-skip-permissions` is on by default whenever `--sandbox` is
used** (`claude --sandbox` and `claude --local --sandbox`), since the Docker
container provides a real filesystem boundary that makes bypass mode
reasonable there. It is **not** applied to `--local` without `--sandbox` (no container
boundary, so normal permission prompting still applies). Opt out with
`--no-skip-permissions`:
```bash
claude --sandbox --no-skip-permissions
claude --local --sandbox --no-skip-permissions
```

**Default permission mode / plan mode:** use the native `--permission-mode`
flag (accepts `default`, `acceptEdits`, `plan`, `bypassPermissions`), e.g.
`claude --local --permission-mode plan`. Note this may conflict with
`--dangerously-skip-permissions` if both are active in a sandboxed mode —
skip-permissions takes precedence when both are present.

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
- **`--model` is only meaningful with `--local`.** Passing it without
  `--local` is silently ignored.
- **`--bare` and `--dangerously-skip-permissions` have different defaults per
  mode** — see the flags table under Usage. Worth double-checking with
  `claude --local --help`-equivalent review of the function source if you're
  ever unsure what a given invocation will actually run.
