# Multi-Agent Devcontainer für Windows + VS Code

Dieser Devcontainer richtet eine reproduzierbare Entwicklungsumgebung für VS Code ein und bereitet optionale CLI-Tools wie Codex, Gemini und Claude vor.

## Ziel

- konsistente Entwicklungsumgebung in VS Code
- Nutzung von Dev Containers unter Windows
- optionale Anmeldung für:
  - Codex
  - Gemini CLI
  - Claude Code
- robuste Standardkonfiguration für Zuhause ohne Proxy
- vorbereitete Schalter für Corporate / Proxy / Root-CA

---

## Voraussetzungen

- Windows 11
- Docker Desktop
- VS Code
- VS Code Extension **Dev Containers**
- WSL2 installiert
- Docker Desktop mit WSL-Integration aktiviert

---

## Schnellstart

1. Repository in VS Code öffnen
2. Command Palette öffnen
3. `Dev Containers: Rebuild and Reopen in Container`
4. Warten, bis der Container gestartet ist
5. Im Container-Terminal prüfen:

```bash
codex --version
gemini --version
claude --version
```
