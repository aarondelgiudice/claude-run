# claude-local-sandbox
#
# A sandboxed environment for running Claude Code — either against Anthropic's
# cloud API or a local Ollama model — with the container providing real
# filesystem/process isolation from the host machine.
#
# Build:
#   docker build -t claude-local-sandbox .
#
# NOTE: the `useradd -u` value below is pinned to a specific host UID so that
# bind-mounted files (e.g. ~/.claude, ~/.claude.json) retain correct ownership
# inside the container. Run `id -u` on your host and update the value below if
# it differs from 501 (the default first-user UID on macOS).

FROM node:22-slim
RUN apt-get update && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code
RUN useradd -m -u 502 -s /bin/bash agent && chmod -R 777 /home/agent
WORKDIR /work
USER agent
ENTRYPOINT ["claude"]
