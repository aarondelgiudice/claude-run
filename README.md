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
claude                                              # normal, cloud, bare metal
claude --sandbox                                    # cloud model, Docker-isolated
claude --local                                      # local model (qwen3-coder), bare metal
claude --local --model qwen2.5-coder:14b             # local model, different model
claude --local --sandbox                            # local model, Docker-isolated
```

All native `claude` flags (`--resume`, etc.) pass through normally, e.g.:
```bash
claude --sandbox --resume
```

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
