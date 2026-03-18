[CmdletBinding()]
param()

$stateRoot = Join-Path $HOME ".devcontainer-agent-state\remote-test"
$directories = @(
  (Join-Path $stateRoot "codex"),
  (Join-Path $stateRoot "gemini"),
  (Join-Path $stateRoot "gemini-config"),
  (Join-Path $stateRoot "claude"),
  (Join-Path $stateRoot "claude-persist")
)

foreach ($directory in $directories) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

Write-Host "[prepare-agent-state] ensured host state directories under $stateRoot"
