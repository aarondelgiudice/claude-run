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
#   claude --sandbox [native claude args]                           # cloud model, run inside Docker
#   claude --local [--model <name>] [native claude args]            # local model (Ollama), bare metal
#   claude --local --sandbox [--model <name>] [native claude args]  # local model, Docker
#
# EXAMPLES:
#   claude --resume
#   claude --sandbox --resume
#   claude --local
#   claude --local --model qwen2.5-coder:14b
#   claude --local --sandbox
#   claude --local --sandbox --model qwen2.5-coder:14b --resume
#
# NOTES:
#   - --sandbox (cloud) mounts your host ~/.claude and ~/.claude.json so it can
#     reuse your existing login. This requires the Dockerfile's `agent` user to
#     be built with the same UID as your host user (see Dockerfile comments).
#   - --local and --local --sandbox always run with --dangerously-skip-permissions.
#     This is opt-in: only triggered by --local, never by plain `claude` or
#     `claude --sandbox` alone.
#   - --model only has an effect when combined with --local; it's silently
#     ignored otherwise.
claude() {
  local use_local=""
  local use_sandbox=""
  local model="qwen3-coder"
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
      *)
        native_args+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "$use_local" && -n "$use_sandbox" ]]; then
    # Local model, Docker-sandboxed
    docker run -it --rm \
      -v "$(pwd)":/work \
      -e ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
      -e ANTHROPIC_AUTH_TOKEN=ollama \
      -e ANTHROPIC_API_KEY="" \
      -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      claude-local-sandbox --dangerously-skip-permissions --model "$model" "${native_args[@]}"

  elif [[ -n "$use_local" ]]; then
    # Local model, bare metal
    ANTHROPIC_BASE_URL=http://localhost:11434 \
    ANTHROPIC_AUTH_TOKEN=ollama \
    ANTHROPIC_API_KEY="" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    command claude --model "$model" "${native_args[@]}"

  elif [[ -n "$use_sandbox" ]]; then
    # Cloud model, Docker-sandboxed — reuses your existing Claude login
    docker run -it --rm \
      -v "$(pwd)":/work \
      -v ~/.claude:/home/agent/.claude \
      -v ~/.claude.json:/home/agent/.claude.json \
      claude-local-sandbox "${native_args[@]}"

  else
    # Normal — untouched
    command claude "${native_args[@]}"
  fi
}
