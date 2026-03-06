<# 
Startet Px als lokalen Auth-Proxy für Corporate Proxies (PAC + Kerberos/NTLM via Windows/SSPI).

- Default: liest optional .devcontainer\devcontainer.env (oder .example) und übernimmt PX_PAC_URL/PX_PORT.
- Startet Px mit --hostonly (damit Docker Container/VMs Px nutzen können). :contentReference[oaicite:2]{index=2}
- Wenn keine PAC URL angegeben ist, kann Px Proxy-Definitionen aus Windows Internet Options übernehmen. :contentReference[oaicite:3]{index=3}

Aufruf (im Repo):
  powershell -ExecutionPolicy Bypass -File .\.devcontainer\windows\start-px.ps1
  powershell -ExecutionPolicy Bypass -File .\.devcontainer\windows\start-px.ps1 -PacUrl "https://proxy.firma.local/proxy.pac" -Port 3128 -Foreground

Hinweis: Container setzen dann HTTP(S)_PROXY auf http://host.docker.internal:3128
#>

[CmdletBinding()]
param(
  [string]$PacUrl,
  [int]$Port = 3128,
  [switch]$Foreground,
  [string]$EnvFile
)

function Read-EnvFile {
  param([Parameter(Mandatory=$true)][string]$Path)

  $map = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -eq 0) { return }
    if ($line.StartsWith("#")) { return }

    # Unterstützt: KEY=VALUE
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }

    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()

    # entferne optionale Quotes
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
      $v = $v.Substring(1, $v.Length - 2)
    }

    $map[$k] = $v
  }
  return $map
}

# Repo Root ermitteln (Script liegt in .devcontainer\windows\)
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

# Default env file
if (-not $EnvFile) {
  $candidate1 = Join-Path $repoRoot ".devcontainer\devcontainer.env"
  $candidate2 = Join-Path $repoRoot ".devcontainer\devcontainer.env.example"
  if (Test-Path $candidate1) { $EnvFile = $candidate1 }
  elseif (Test-Path $candidate2) { $EnvFile = $candidate2 }
}

$cfg = @{}
if ($EnvFile) {
  $cfg = Read-EnvFile -Path $EnvFile
}

if (-not $PacUrl -and $cfg.ContainsKey("PX_PAC_URL")) { $PacUrl = $cfg["PX_PAC_URL"] }
if ($cfg.ContainsKey("PX_PORT")) {
  [int]$tmp = 0
  if ([int]::TryParse($cfg["PX_PORT"], [ref]$tmp)) { $Port = $tmp }
}

$px = Get-Command "px" -ErrorAction SilentlyContinue
if (-not $px) {
  Write-Error "Px wurde nicht gefunden (Befehl 'px'). Installiere es oder füge es zum PATH hinzu."
  Write-Host  "Projekt: https://github.com/genotrance/px"
  exit 1
}

$args = @("--port=$Port", "--hostonly")

# PAC ist optional: wenn du es nicht angibst, kann Px Proxy-Infos aus Windows Internet Options übernehmen. :contentReference[oaicite:4]{index=4}
if ($PacUrl -and $PacUrl.Trim().Length -gt 0) {
  $args += "--pac=$PacUrl"
}

# Optional: Extra Args aus Env (z.B. --noproxy=... oder Logging)
if ($cfg.ContainsKey("PX_EXTRA_ARGS") -and $cfg["PX_EXTRA_ARGS"].Trim().Length -gt 0) {
  # Split on whitespace (simple)
  $extra = $cfg["PX_EXTRA_ARGS"].Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
  $args += $extra
}

$logDir = Join-Path $repoRoot ".devcontainer\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir ("px-{0}.log" -f $Port)

$proxyUrl = "http://host.docker.internal:{0}" -f $Port
Write-Host "RepoRoot: $repoRoot"
Write-Host "EnvFile : $EnvFile"
Write-Host "Proxy   : $proxyUrl"
Write-Host "Args    : $($args -join ' ')"
Write-Host "Log     : $logFile"

if ($Foreground) {
  Write-Host "Starte Px im Vordergrund (CTRL+C zum Stoppen)..."
  & $px.Source @args 2>&1 | Tee-Object -FilePath $logFile -Append
} else {
  Write-Host "Starte Px im Hintergrund..."
  Start-Process -FilePath $px.Source -ArgumentList $args -NoNewWindow `
    -RedirectStandardOutput $logFile -RedirectStandardError $logFile | Out-Null
  Write-Host "Px läuft. (Log: $logFile)"
}