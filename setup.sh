#!/usr/bin/env bash
set -euo pipefail

# setup.sh: one-time setup for claude-run on a new machine.
# Safe to re-run: build is idempotent, and the .zshrc line is only added once.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="source \"$SCRIPT_DIR/claude-run.zsh\""

echo "== claude-run setup =="
echo

# --- 1. Check prerequisites ---
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found. Install Docker Desktop first: https://www.docker.com/products/docker-desktop/"; exit 1; }
command -v claude >/dev/null 2>&1 || echo "WARNING: 'claude' CLI not found on PATH. Install it: npm install -g @anthropic-ai/claude-code"

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon isn't running. Start Docker Desktop and re-run this script."
  exit 1
fi

# --- 1b. Install Ollama if missing ---
if ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama not found."
  read -r -p "Install it now via Homebrew? [Y/n] " REPLY
  if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "ERROR: Homebrew not found. Install Ollama manually: https://ollama.com/download"
      exit 1
    fi
    brew install --cask ollama
    open -a /Applications/Ollama.app 2>/dev/null || echo "NOTE: couldn't auto-launch Ollama yet. Open it manually the first time."
    echo "Waiting for Ollama to start..."
    sleep 5
  else
    echo "Skipping. Install manually from https://ollama.com/download, then re-run this script."
    exit 1
  fi
fi

# --- 1c. Set Ollama performance env vars (launchctl setenv; cleared on reboot, re-run this script after one) ---
echo
echo "Setting Ollama performance env vars via launchctl..."
launchctl setenv OLLAMA_FLASH_ATTENTION 1
launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0
launchctl setenv OLLAMA_KEEP_ALIVE 60m

# These only take effect on (re)start, so restart Ollama if it's already running.
if pgrep -x "Ollama" >/dev/null 2>&1; then
  echo "Restarting Ollama to apply env vars..."
  osascript -e 'quit app "Ollama"' 2>/dev/null || true
  sleep 2
fi
open -a /Applications/Ollama.app 2>/dev/null || echo "NOTE: couldn't auto-launch the Ollama app. Start it manually."
sleep 3

# --- 2. Check UID match against Dockerfile ---
HOST_UID="$(id -u)"
DOCKERFILE_UID="$(grep -oE 'useradd -m -u [0-9]+' "$SCRIPT_DIR/Dockerfile" | grep -oE '[0-9]+$' || echo "")"

if [[ -n "$DOCKERFILE_UID" && "$HOST_UID" != "$DOCKERFILE_UID" ]]; then
  echo "Host UID ($HOST_UID) differs from Dockerfile UID ($DOCKERFILE_UID)."
  read -r -p "Update Dockerfile to use UID $HOST_UID? [Y/n] " REPLY
  if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
    sed -i.bak "s/useradd -m -u $DOCKERFILE_UID/useradd -m -u $HOST_UID/" "$SCRIPT_DIR/Dockerfile"
    rm -f "$SCRIPT_DIR/Dockerfile.bak"
    echo "Updated Dockerfile to UID $HOST_UID."
  else
    echo "Skipping UID update. --sandbox mode may show ownership mismatches on mounted ~/.claude files."
  fi
fi

# --- 3. Build the image ---
echo
echo "Building claude-run image..."
docker build -t claude-run "$SCRIPT_DIR"

# --- 4. Wire up the shell function ---
echo
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
  echo "~/.zshrc already sources claude-run.zsh; skipping."
else
  echo "" >> "$ZSHRC"
  echo "# claude-run" >> "$ZSHRC"
  echo "$SOURCE_LINE" >> "$ZSHRC"
  echo "Added source line to ~/.zshrc."
fi

# --- 5. Pull default local model ---
if command -v ollama >/dev/null 2>&1; then
  echo
  read -r -p "Pull default local model (qwen3-coder) now? [Y/n] " REPLY
  if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
    ollama pull qwen3-coder
  fi
fi

echo
echo "== Setup complete =="
echo "Run 'source ~/.zshrc' (or open a new terminal), then try: claude --api local"
