$ErrorActionPreference = 'Stop'
$agentDirectory = $PSScriptRoot
if (-not (Test-Path -LiteralPath "$agentDirectory/.venv/Scripts/python.exe")) {
    python -m venv "$agentDirectory/.venv"
    if ($LASTEXITCODE -ne 0) { throw 'Python venv creation failed. Install Python 3.10+ first.' }
}
& "$agentDirectory/.venv/Scripts/python.exe" -m pip install -r "$agentDirectory/requirements.txt"
if ($LASTEXITCODE -ne 0) { throw 'MCP dependency installation failed.' }
$pythonPath = Join-Path $agentDirectory '.venv/Scripts/python.exe'
$serverPath = Join-Path $agentDirectory 'server.py'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$json = @{ mcpServers = @{ 'league-of-soccer' = @{ command = $pythonPath; args = @($serverPath) } } } | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText((Join-Path $agentDirectory 'mcp-config.json'), $json, $utf8)
$pythonLiteral = ConvertTo-Json -InputObject $pythonPath -Compress
$serverLiteral = ConvertTo-Json -InputObject $serverPath -Compress
$toml = @"
[mcp_servers.league-of-soccer]
command = $pythonLiteral
args = [$serverLiteral]
"@
[System.IO.File]::WriteAllText((Join-Path $agentDirectory 'codex-config.toml'), $toml, $utf8)
Write-Output 'Ready. Local mcp-config.json and codex-config.toml now use this checkout path.'
