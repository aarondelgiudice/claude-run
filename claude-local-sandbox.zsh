# claude-local-sandbox — wraps `claude` with --local and --sandbox modes.
#
# Setup (one-time per machine):
#   1. Build the image:  docker build -t claude-local-sandbox .
#      (from the directory containing the Dockerfile in this repo)
#   2. Add this file to your shell config, e.g. in ~/.zshrc:
#        source /path/to/claude-local-sandbox.zsh
#   3. Make sure Ollama is running locally (for --local mode) and Docker
#      Desktop is running (for --sandbox mode).
#
# USAGE:
#   claude [native claude args]                                     # normal, cloud, bare metal
#   claude --sandbox [native claude args]                           # cloud model, Docker, bypass permissions on
#   claude --local [--model <name>] [native claude args]            # local model, bare metal, --bare on
#   claude --local --sandbox [--model <name>] [native claude args]  # local model, Docker, --bare + bypass permissions on
#
# DEFAULTS (see README for full details):
#   --bare is ON by default for --local and --local --sandbox. Opt out: --no-bare
#   --dangerously-skip-permissions is ON by default for --sandbox and
#     --local --sandbox (never for bare-metal --local). Opt out: --no-skip-permissions
#
# EXAMPLES:
#   claude --resume
#   claude --sandbox --resume
#   claude --local
#   claude --local --model qwen2.5-coder:14b
#   claude --local --sandbox
#   claude --local --sandbox --model qwen2.5-coder:14b --resume
#   claude --local --no-bare
#   claude --sandbox --no-skip-permissions
claude() {
  local use_local=""
  local use_sandbox=""
  local model="qwen3-coder"
  local bare_flag="--bare"
  local skip_perms="1"
  local native_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local)
        use_local="1"
        shift
        ;;
      --sandbox)
        use_sandbox="1"
        shift
        ;;
      --model)
        model="$2"
        shift 2
        ;;
      --no-bare)
        bare_flag=""
        shift
        ;;
      --no-skip-permissions)
        skip_perms=""
        shift
        ;;
      *)
        native_args+=("$1")
        shift
        ;;
    esac
  done

  local perm_flag=""
  [[ -n "$skip_perms" && -n "$use_sandbox" ]] && perm_flag="--dangerously-skip-permissions"

  if [[ -n "$use_local" && -n "$use_sandbox" ]]; then
    # Local model, Docker-sandboxed — bare + skip-permissions on by default
    docker run -it --rm \
      -v "$(pwd)":/work \
      -e ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
      -e ANTHROPIC_AUTH_TOKEN=ollama \
      -e ANTHROPIC_API_KEY="" \
      -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      claude-local-sandbox $perm_flag $bare_flag --model "$model" "${native_args[@]}"

  elif [[ -n "$use_local" ]]; then
    # Local model, bare metal — bare on by default, skip-permissions NOT applied (not sandboxed)
    ANTHROPIC_BASE_URL=http://localhost:11434 \
    ANTHROPIC_AUTH_TOKEN=ollama \
    ANTHROPIC_API_KEY="" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    command claude $bare_flag --model "$model" "${native_args[@]}"

  elif [[ -n "$use_sandbox" ]]; then
    # Cloud model, Docker-sandboxed — skip-permissions on by default, bare NOT applied
    docker run -it --rm \
      -v "$(pwd)":/work \
      -v ~/.claude:/home/agent/.claude \
      -v ~/.claude.json:/home/agent/.claude.json \
      claude-local-sandbox $perm_flag "${native_args[@]}"

  else
    # Normal — untouched
    command claude "${native_args[@]}"
  fi
}
