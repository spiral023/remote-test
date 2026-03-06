# Multi-Agent Devcontainer: Codex + Claude Code + Gemini CLI + Dev-Basics
FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

SHELL ["/bin/bash", "-lc"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git openssh-client ca-certificates curl \
    build-essential jq ripgrep unzip \
    python3 python3-venv python3-pip \
    git-lfs \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN npm i -g @openai/codex @google/gemini-cli

ENV PATH="/home/node/.local/agent-bin:/home/node/.local/bin:${PATH}"
