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
#   claude [native claude args]                                     # normal, cloud
#   claude --sandbox [native claude args]                           # cloud model, Docker, bypass permissions on
#   claude --local [--model <name>] [native claude args]            # local model, --bare + --exclude-dynamic-system-prompt-sections on
#   claude --local --sandbox [--model <name>] [native claude args]  # local model, Docker, --bare + --exclude-dynamic-system-prompt-sections + bypass permissions on
#   claude --api <provider> [native claude args]                    # external API (e.g. deepseek)
#   claude --api <provider> --sandbox [native claude args]          # external API, Docker, bypass permissions on
#
# DEFAULTS (see README for full details):
#   --bare (skips most tool calls to run faster) is ON by default for --local
#     and --local --sandbox. Opt out: --no-bare
#   --exclude-dynamic-system-prompt-sections is ON by default for --local and
#     --local --sandbox. Opt out: --no-exclude-dynamic-system-prompt-sections
#   --dangerously-skip-permissions is ON by default for --sandbox and
#     --local --sandbox (never for --local without --sandbox). Opt out: --no-skip-permissions
#
# EXTERNAL APIS:
#   --api <provider> routes to an external Anthropic-compatible API instead of
#     the cloud API or a local model. Known provider: deepseek (set
#     $DEEPSEEK_API_KEY first). --api and --local are mutually exclusive.
#     --bare and --exclude-dynamic-system-prompt-sections do NOT apply (those
#     are local-model tweaks). --api may combine with --sandbox.
#
# EXAMPLES:
#   claude --resume
#   claude --sandbox --resume
#   claude --local
#   claude --local --model qwen2.5-coder:14b
#   claude --local --sandbox
#   claude --local --sandbox --model qwen2.5-coder:14b --resume
#   claude --local --no-bare
#   claude --local --no-exclude-dynamic-system-prompt-sections
#   claude --sandbox --no-skip-permissions
#   claude --api deepseek
#   claude --api deepseek --model deepseek-v4-flash
#   claude --api deepseek --sandbox
claude() {
  local use_local=""
  local use_sandbox=""
  local model="qwen3-coder"
  local model_set=""
  local api_provider=""
  local bare_flag="--bare"
  local exclude_dynamic_flag="--exclude-dynamic-system-prompt-sections"
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
        model_set="1"
        shift 2
        ;;
      --api)
        api_provider="$2"
        shift 2
        ;;
      --no-bare)
        bare_flag=""
        shift
        ;;
      --no-exclude-dynamic-system-prompt-sections)
        exclude_dynamic_flag=""
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

  # --api <provider>: route to an external Anthropic-compatible API.
  # To add a provider, add a case below with its base URL, key env var, and models.
  local api_base_url="" api_key="" api_model="" api_opus="" api_sonnet="" api_haiku="" api_subagent="" api_effort=""
  if [[ -n "$api_provider" ]]; then
    if [[ -n "$use_local" ]]; then
      echo "claude: --api and --local are mutually exclusive" >&2
      return 1
    fi
    local api_key_var="" api_default_model=""
    case "$api_provider" in
      deepseek)
        api_base_url="https://api.deepseek.com/anthropic"
        api_key_var="DEEPSEEK_API_KEY"
        api_default_model="deepseek-v4-pro"
        api_opus="deepseek-v4-pro"
        api_sonnet="deepseek-v4-pro"
        api_haiku="deepseek-v4-flash"
        api_subagent="deepseek-v4-flash"
        api_effort="max"
        ;;
      *)
        echo "claude: unknown --api provider '$api_provider' (known: deepseek)" >&2
        return 1
        ;;
    esac
    api_key="${(P)api_key_var}"
    if [[ -z "$api_key" ]]; then
      echo "claude: \$$api_key_var is not set (required for --api $api_provider)" >&2
      return 1
    fi
    api_model="$api_default_model"
    [[ -n "$model_set" ]] && api_model="$model"
  fi

  if [[ -n "$api_provider" && -n "$use_sandbox" ]]; then
    # External API, Docker-sandboxed — skip-permissions on by default; API vars passed via -e
    docker run -it --rm \
      -v "$(pwd)":/work \
      -e ANTHROPIC_BASE_URL="$api_base_url" \
      -e ANTHROPIC_AUTH_TOKEN="$api_key" \
      -e ANTHROPIC_API_KEY="" \
      -e ANTHROPIC_MODEL="$api_model" \
      -e ANTHROPIC_DEFAULT_OPUS_MODEL="$api_opus" \
      -e ANTHROPIC_DEFAULT_SONNET_MODEL="$api_sonnet" \
      -e ANTHROPIC_DEFAULT_HAIKU_MODEL="$api_haiku" \
      -e CLAUDE_CODE_SUBAGENT_MODEL="$api_subagent" \
      -e CLAUDE_CODE_EFFORT_LEVEL="$api_effort" \
      claude-local-sandbox $perm_flag "${native_args[@]}"

  elif [[ -n "$api_provider" ]]; then
    # External API on host — vars set inline (never exported), so --local vars stay untouched
    ANTHROPIC_BASE_URL="$api_base_url" \
    ANTHROPIC_AUTH_TOKEN="$api_key" \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_MODEL="$api_model" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$api_opus" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$api_sonnet" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$api_haiku" \
    CLAUDE_CODE_SUBAGENT_MODEL="$api_subagent" \
    CLAUDE_CODE_EFFORT_LEVEL="$api_effort" \
    command claude "${native_args[@]}"

  elif [[ -n "$use_local" && -n "$use_sandbox" ]]; then
    # Local model, Docker-sandboxed — bare + exclude-dynamic-system-prompt-sections + skip-permissions on by default
    docker run -it --rm \
      -v "$(pwd)":/work \
      -e ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
      -e ANTHROPIC_AUTH_TOKEN=ollama \
      -e ANTHROPIC_API_KEY="" \
      -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      claude-local-sandbox $perm_flag $bare_flag $exclude_dynamic_flag --model "$model" "${native_args[@]}"

  elif [[ -n "$use_local" ]]; then
    # Local model — bare + exclude-dynamic-system-prompt-sections on by default, skip-permissions NOT applied (not sandboxed)
    ANTHROPIC_BASE_URL=http://localhost:11434 \
    ANTHROPIC_AUTH_TOKEN=ollama \
    ANTHROPIC_API_KEY="" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    command claude $bare_flag $exclude_dynamic_flag --model "$model" "${native_args[@]}"

  elif [[ -n "$use_sandbox" ]]; then
    # Cloud model, Docker-sandboxed — skip-permissions on by default, bare + exclude-dynamic-system-prompt-sections NOT applied
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
