# Devcontainer Notes

Diese Datei ergaenzt die Root-`README.md` um containernahe Betriebsdetails. Die GitHub-Uebersicht und der Schnellstart stehen in der Root-Dokumentation.

## Persistenz

Der Devcontainer bind-mountet Agent-State vom Host in den Container:

- macOS/Linux: `$HOME/.devcontainer-agent-state/remote-test/`
- Windows: `%USERPROFILE%\\.devcontainer-agent-state\\remote-test\\`

`initializeCommand` legt die benoetigten Host-Ordner vor dem eigentlichen `docker run` automatisch an. Dadurch schlagen neue Clients nicht mehr an fehlenden Bind-Mount-Quellen fehl.

Wichtige Mounts:

- `~/.codex`
- `~/.gemini`
- `~/.config/gemini`
- `~/.claude`
- `~/.persist/claude`

## Wrapper und Bootstrap

`initializeCommand` bereitet zuerst die Host-Mounts vor. Danach rufen `postCreateCommand` und `postStartCommand` beide `.devcontainer/scripts/bootstrap.sh` auf. Das Skript:

- erstellt Wrapper fuer `codex`, `gemini`, `claude`, `claude-login`, `claude-bridge` und `agent-doctor`
- legt zusaetzliche Shims unter `~/.local/bin` an, damit die Wrapper im `PATH` vor den echten Binaries liegen
- synchronisiert Claude-Root-Config zwischen `~/.claude.json` und `~/.persist/claude/.claude.json`
- setzt bei vorhandenem Claude-Login den benoetigten Runtime-Zustand fuer interaktives `claude`

Bootstrap manuell erneut ausfuehren:

```bash
bash .devcontainer/scripts/bootstrap.sh
```

## Claude Login im Container

Bevorzugter Login-Befehl:

```bash
claude-login
```

Der Helper kompensiert mehrere container-spezifische Claude-Eigenheiten:

- `localhost` kann im Container IPv6-first aufloesen
- aktuelle Claude-Versionen drucken nicht zwingend mehr den lokalen Callback-Port aus
- `claude auth status` und interaktives `claude` haengen beide an `~/.claude.json`, aber interaktives `claude` braucht zusaetzlich abgeschlossene Onboarding-Flags

Deshalb macht `claude-login` folgendes automatisch:

- startet Login mit `--dns-result-order=ipv4first`
- erkennt den echten lokalen Callback-Port ueber die offenen Listener des Claude-Prozesses
- startet nur bei Bedarf die IPv4->IPv6-Bridge
- startet bei einem fehlgeschlagenen ersten Browser-Login automatisch einen zweiten Versuch
- spiegelt `~/.claude.json` in den persistenten Claude-Mount
- setzt `theme`, `hasCompletedOnboarding` und `lastOnboardingVersion`, wenn bereits gueltige Claude-OAuth-Daten vorliegen
- startet nach erfolgreichem Login direkt `claude`

Nur Login ohne anschliessenden Start:

```bash
claude-login --login-only
```

## Claude Troubleshooting

Diagnose starten:

```bash
agent-doctor
claude auth status
```

Wichtige Unterscheidung:

- `claude auth status` prueft OAuth
- interaktives `claude` prueft zusaetzlich den lokalen Runtime- und Onboarding-Zustand

Wenn `claude` nach erfolgreichem Login noch einen Dialog zeigt, ist das oft nur der Workspace-Trust-Prompt und kein erneuter Auth-Fehler.

## Proxy und Zertifikate

- Standard privat: `USE_LOCAL_PROXY=0`, `USE_CORP_CA=0`
- Corporate mit Px: `USE_LOCAL_PROXY=1` und `.devcontainer/windows/start-px.ps1`
- Corporate mit direktem Proxy: `HTTP_PROXY` und `HTTPS_PROXY` in `.devcontainer/devcontainer.env`
- Corporate CA: Zertifikate in `.devcontainer/certs/*.crt` und `USE_CORP_CA=1`

Hilfsskripte:

```bash
bash .devcontainer/scripts/proxy.sh
bash .devcontainer/scripts/corp-ca.sh
```

## Hinweise

- Nicht fuer GitHub Codespaces gedacht, da lokale Bind-Mounts verwendet werden
- `.devcontainer/devcontainer.env` und `.devcontainer/certs/*` bleiben lokal und werden nicht committed
