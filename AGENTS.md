# Repository Guidelines

## Project Structure & Module Organization
This repository is a devcontainer setup, not an application package. The root `README.md` is the primary GitHub-facing overview. Core implementation lives in `.devcontainer/`:

- `.devcontainer/devcontainer.json`: container definition, mounts, VS Code extensions, and `postCreateCommand`.
- `.devcontainer/Dockerfile`: base image and installed CLI tooling.
- `.devcontainer/scripts/`: bootstrap, proxy, CA, wrapper, and Claude helper scripts.
- `.devcontainer/windows/`: Windows-side helper for starting `px`.
- `.devcontainer/README.md`: container-focused operational notes.

There is no `src/` or `tests/` directory yet. Add new automation next to the existing shell or Node helpers unless a larger module structure becomes necessary.

## Build, Test, and Development Commands
- `Dev Containers: Rebuild and Reopen in Container`: primary way to build and start the environment in VS Code.
- `bash .devcontainer/scripts/bootstrap.sh`: re-runs local wrapper/bootstrap setup inside the container.
- `bash .devcontainer/scripts/proxy.sh`: applies proxy environment configuration when `USE_LOCAL_PROXY=1`.
- `bash .devcontainer/scripts/corp-ca.sh`: installs corporate CA certificates when `USE_CORP_CA=1`.
- `claude-login`: preferred Claude browser login flow in the container.
- `claude auth status`: verifies Claude auth state separately from the interactive TTY startup flow.
- `codex --version && gemini --version && claude --version`: quick smoke test after container startup.

## Coding Style & Naming Conventions
Use LF line endings; `.gitattributes` enforces this for shell and devcontainer files. Match the existing style:

- Shell: `#!/usr/bin/env bash`, `set -euo pipefail`, lowercase function names, descriptive log prefixes.
- Node scripts: ES modules (`.mjs`), `const`/`let`, clear helper names like `tryExtractPort`.
- JSON and Docker files: 2-space indentation.
- File names: kebab-case for scripts such as `.devcontainer/scripts/claude-ipv4-bridge.mjs`.

## Documentation Conventions
- Keep `README.md` optimized for GitHub readers: fast orientation, quick start, architecture, troubleshooting.
- Keep `AGENTS.md` focused on maintainer guidance, not end-user onboarding.
- When Claude login behavior changes, update `README.md` and `.devcontainer/README.md` in the same change.
- Prefer documenting concrete file paths and commands over abstract descriptions.

## Testing Guidelines
There is no automated test suite yet. Validate changes with focused manual checks:

- Rebuild the devcontainer after changing `Dockerfile` or `devcontainer.json`.
- Run the affected script directly, for example `bash .devcontainer/scripts/bootstrap.sh`.
- Verify tool wrappers and env handling with version checks or the relevant login flow.
- For Claude-specific changes, test both `claude auth status` and an interactive `claude` start, because onboarding state and auth state are not identical.

If you add tests later, keep them close to the scripts they cover and name them after the target file.

## Commit & Pull Request Guidelines
Current history uses short, imperative commit subjects, for example: `Add multi-agent devcontainer setup with necessary configurations and scripts`. Follow that pattern.

PRs should include:

- a concise summary of the container or script change,
- any required environment changes (`.devcontainer/devcontainer.env`, certificates, proxy settings),
- manual verification steps and results,
- screenshots only when changing editor/devcontainer UX.

## Security & Configuration Tips
Do not commit `.devcontainer/devcontainer.env` or files under `.devcontainer/certs/`. Keep secrets, proxy credentials, and corporate CA material local only.
