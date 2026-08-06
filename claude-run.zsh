# claude-run: wraps `claude` with --api and --sandbox modes.
#
# Setup (one-time per machine):
#   1. Build the image:  docker build -t claude-run .
#      (from the directory containing the Dockerfile in this repo)
#   2. Add this file to your shell config, e.g. in ~/.zshrc:
#        source /path/to/claude-run.zsh
#   3. Make sure Ollama is running locally (for --api local) and Docker
#      Desktop is running (for --sandbox).
#
# USAGE:
#   claude [native claude args]                                     # cloud (Anthropic)
#   claude --sandbox [native claude args]                           # cloud, Docker, bypass permissions on
#   claude --api local [--model <name>] [native claude args]        # Ollama, --bare + --exclude-dynamic-system-prompt-sections on
#   claude --api deepseek [native claude args]                      # external API (DeepSeek)
#   claude --api <backend> --sandbox [native claude args]           # any --api backend, Docker, bypass permissions on
#
# DEFAULTS (see README for full details):
#   --bare (skips most tool calls to run faster) is ON by default for --api local.
#     Opt out: --no-bare
#   --exclude-dynamic-system-prompt-sections is ON by default for --api local.
#     Opt out: --no-exclude-dynamic-system-prompt-sections
#   --dangerously-skip-permissions is ON by default whenever --sandbox is used
#     (any backend). Opt out: --no-skip-permissions
#
# BACKENDS (--api <backend>):
#   local      Ollama on this machine (default model qwen3-coder; --model to change).
#              No API key needed. --bare + --exclude-dynamic-system-prompt-sections
#              default on (local models are slow with the full tool schema).
#   deepseek   DeepSeek's Anthropic-compatible API. Set $DEEPSEEK_API_KEY first.
#   kimi       Kimi k3 (Moonshot, 1M context). Set $KIMI_API_KEY first.
#   kimi-k2.7  Kimi k2.7-code (Moonshot, 256K context). Set $KIMI_API_KEY first.
#              REQUIRES Thinking ON in Claude Code (press Tab) or it rejects requests.
#   Any --api backend may combine with --sandbox for Docker isolation.
#
#   In-session, /model flips models live where a backend maps two: deepseek
#   (Opus=Pro, Sonnet=Flash) and kimi-k2.7 (Opus=k2.7-code, Sonnet=highspeed).
#   The endpoint is fixed per session. You cannot reach Anthropic models. You
#   cannot cross context-window sizes (k3 vs k2.7) mid-session.
#
# EXAMPLES:
#   claude --resume
#   claude --sandbox --resume
#   claude --api local
#   claude --api local --model qwen2.5-coder:14b
#   claude --api local --sandbox
#   claude --api local --sandbox --model qwen2.5-coder:14b --resume
#   claude --api local --no-bare
#   claude --api local --no-exclude-dynamic-system-prompt-sections
#   claude --sandbox --no-skip-permissions
#   claude --api deepseek
#   claude --api deepseek --model deepseek-v4-flash
#   claude --api deepseek --sandbox
#   claude --api kimi
#   claude --api kimi-k2.7
#   claude --api kimi --sandbox
claude() {
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

  # --api <backend>: pick where requests go. Each backend sets its env below.
  # To add a hosted provider, add a case with its base URL, key env var, and models.
  local api_base_url="" api_key="" api_model="" api_opus="" api_sonnet="" api_haiku=""
  local api_fable="" api_subagent="" api_max_context=""
  local api_disable_nonessential=""
  local -a api_env api_cli_flags
  if [[ -n "$api_provider" ]]; then
    local api_key_var="" api_default_model=""
    case "$api_provider" in
      local)
        # Ollama on this machine. Base URL differs inside the container.
        if [[ -n "$use_sandbox" ]]; then
          api_base_url="http://host.docker.internal:11434"
        else
          api_base_url="http://localhost:11434"
        fi
        api_key="ollama"                # dummy token; no key env var to look up
        api_disable_nonessential="1"
        # What Ollama actually serves (num_ctx). Overridable per machine; the
        # default matches qwen3-coder's served window. Claude Code otherwise
        # assumes 200k for this unrecognized model.
        api_max_context="${CLAUDE_RUN_LOCAL_CONTEXT:-262144}"
        # Array, not a string: zsh does not word-split unquoted scalars, so a
        # single "--a --b" string would reach claude as one bogus option.
        # Empty $bare_flag/$exclude_dynamic_flag (from --no-*) elide to nothing.
        api_cli_flags=($bare_flag $exclude_dynamic_flag --model $model)
        ;;
      deepseek)
        # Pro on the Opus alias, Flash on Sonnet -> flip Pro<->Flash live via
        # /model. (Both share a context window, so this is safe.)
        api_base_url="https://api.deepseek.com/anthropic"
        api_key_var="DEEPSEEK_API_KEY"
        api_default_model="deepseek-v4-pro"
        api_opus="deepseek-v4-pro"
        api_sonnet="deepseek-v4-flash"
        api_haiku="deepseek-v4-flash"
        api_fable="deepseek-v4-pro"
        api_subagent="deepseek-v4-flash"
        api_max_context="1048576"       # pro and flash are both ~1M
        ;;
      kimi)
        # Kimi k3 (1M context). Thinking on by default; works out of the box.
        api_base_url="https://api.moonshot.ai/anthropic"
        api_key_var="KIMI_API_KEY"
        api_default_model="kimi-k3"
        api_opus="kimi-k3"
        api_sonnet="kimi-k3"
        api_haiku="kimi-k3"
        api_fable="kimi-k3"
        api_subagent="kimi-k3"
        api_max_context="1048576"
        ;;
      kimi-k2.7)
        # Both k2.7 models are 256K and REQUIRE Thinking ON (press Tab in
        # Claude Code); with thinking off they reject requests. Quality on the
        # Opus alias, highspeed on Sonnet -> flip quality<->speed live via /model.
        api_base_url="https://api.moonshot.ai/anthropic"
        api_key_var="KIMI_API_KEY"
        api_default_model="kimi-k2.7-code"
        api_opus="kimi-k2.7-code"
        api_sonnet="kimi-k2.7-code-highspeed"
        api_haiku="kimi-k2.7-code-highspeed"
        api_fable="kimi-k2.7-code"
        api_subagent="kimi-k2.7-code-highspeed"
        api_max_context="262144"
        ;;
      *)
        echo "claude: unknown --api backend '$api_provider' (known: local, deepseek, kimi, kimi-k2.7)" >&2
        return 1
        ;;
    esac

    # Hosted providers read a key from an env var; local uses its dummy token.
    if [[ -n "$api_key_var" ]]; then
      api_key="${(P)api_key_var}"
      if [[ -z "$api_key" ]]; then
        echo "claude: \$$api_key_var is not set (required for --api $api_provider)" >&2
        return 1
      fi
    fi

    # Hosted providers carry the model in ANTHROPIC_MODEL; local rides --model.
    if [[ -n "$api_default_model" ]]; then
      api_model="$api_default_model"
      [[ -n "$model_set" ]] && api_model="$model"
    fi

    # Hosted models: soft effort default via the --effort launch flag, which
    # in-session /effort can still override (unlike CLAUDE_CODE_EFFORT_LEVEL,
    # which would lock it). Change the launch default with $CLAUDE_RUN_EFFORT.
    # Not applied to local: forcing high effort on a slow local model hurts.
    if [[ "$api_provider" != "local" ]]; then
      api_cli_flags+=(--effort "${CLAUDE_RUN_EFFORT:-xhigh}")
    fi

    # Build the env once; append only the vars this backend actually sets.
    api_env=(
      ANTHROPIC_BASE_URL="$api_base_url"
      ANTHROPIC_AUTH_TOKEN="$api_key"
      ANTHROPIC_API_KEY=""
    )
    [[ -n "$api_model" ]]              && api_env+=("ANTHROPIC_MODEL=$api_model")
    [[ -n "$api_opus" ]]              && api_env+=("ANTHROPIC_DEFAULT_OPUS_MODEL=$api_opus")
    [[ -n "$api_sonnet" ]]            && api_env+=("ANTHROPIC_DEFAULT_SONNET_MODEL=$api_sonnet")
    [[ -n "$api_haiku" ]]             && api_env+=("ANTHROPIC_DEFAULT_HAIKU_MODEL=$api_haiku")
    [[ -n "$api_fable" ]]             && api_env+=("ANTHROPIC_DEFAULT_FABLE_MODEL=$api_fable")
    [[ -n "$api_subagent" ]]          && api_env+=("CLAUDE_CODE_SUBAGENT_MODEL=$api_subagent")
    [[ -n "$api_max_context" ]]       && api_env+=("CLAUDE_CODE_MAX_CONTEXT_TOKENS=$api_max_context")
    [[ -n "$api_disable_nonessential" ]] && api_env+=("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1")
  fi

  if [[ -n "$api_provider" && -n "$use_sandbox" ]]; then
    # --api backend, Docker-sandboxed. skip-permissions on by default; env via -e.
    local -a docker_env
    local _kv
    for _kv in "${api_env[@]}"; do docker_env+=(-e "$_kv"); done
    docker run -it --rm \
      -v "$(pwd)":/work \
      "${docker_env[@]}" \
      claude-run $perm_flag "${api_cli_flags[@]}" "${native_args[@]}"

  elif [[ -n "$api_provider" ]]; then
    # --api backend on host. env set for this process only (never exported).
    env "${api_env[@]}" claude "${api_cli_flags[@]}" "${native_args[@]}"

  elif [[ -n "$use_sandbox" ]]; then
    # Cloud model, Docker-sandboxed. skip-permissions on by default.
    docker run -it --rm \
      -v "$(pwd)":/work \
      -v ~/.claude:/home/agent/.claude \
      -v ~/.claude.json:/home/agent/.claude.json \
      claude-run $perm_flag "${native_args[@]}"

  else
    # Normal, untouched.
    command claude "${native_args[@]}"
  fi
}
