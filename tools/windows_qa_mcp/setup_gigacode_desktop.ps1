# AI Story RPG Windows QA MCP - GigaCode Desktop, not Cline.
# A local MCP STDIO server MUST be spawned by GigaCode with the generated command/args.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AppExe,
    [switch]$EnableInput
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$exe = (Resolve-Path -LiteralPath $AppExe -ErrorAction Stop).Path
if ([System.IO.Path]::GetFileName($exe).ToLowerInvariant() -ne 'ai_story_reader.exe') { throw 'Only ai_story_reader.exe is allowed' }
$dir = Split-Path -Parent $exe
if (!(Test-Path -LiteralPath (Join-Path $dir 'data') -PathType Container)) { throw 'Missing portable data directory' }
if (!(Test-Path -LiteralPath (Join-Path $dir 'flutter_windows.dll') -PathType Leaf)) { throw 'Missing flutter_windows.dll' }

$qaRoot = Join-Path $env:LOCALAPPDATA 'AIStoryRPG-QA'
$venv = Join-Path $qaRoot 'python'
New-Item -Path $qaRoot -ItemType Directory -Force | Out-Null
if (!(Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe'))) {
    $launcher = $null
    foreach ($candidate in @('py', 'python')) {
        if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
        try {
            # Python itself compares its version; PowerShell version parsing
            # previously rejected Python 3.15 due to a .Trim() type error.
            & $candidate -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) {
                $launcher = $candidate
                Write-Host "Using installed Python via $candidate"
                break
            }
        } catch { }
    }
    if (-not $launcher) { throw 'Python 3.12+ not available via py or python. Check py --version' }
    & $launcher -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create Python virtual environment' }
}
$python = Join-Path $venv 'Scripts\python.exe'
& $python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'MCP virtual environment must use Python 3.12 or newer' }

& $python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Failed to install MCP dependencies; read the pip error above' }

# An ABSOLUTE Python script path is robust even if GigaCode Desktop ignores cwd.
# The old -m tools.windows_qa_mcp.server depended on starting in repository root.
$bootstrap = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'launch_gigacode.py')).Path
$smoke = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'protocol_smoke.py')).Path
Write-Host 'Checking FastMCP tool registration...'
& $python -u $bootstrap --self-check
if ($LASTEXITCODE -ne 0) { throw 'FastMCP tool registration failed; inspect JSON error above' }
Write-Host 'Testing real MCP STDIO handshake from an unrelated working directory...'
& $python -u $smoke
if ($LASTEXITCODE -ne 0) { throw 'MCP STDIO handshake failed; do not configure GigaCode yet' }

$entry = @{
    mcpServers = @{
        'ai-story-rpg-windows-qa' = @{
            command = $python
            args    = @('-u', $bootstrap)
            cwd     = $repo
            env     = @{
                AI_STORY_QA_EXE = $exe
                AI_STORY_QA_OUTPUT = (Join-Path $qaRoot 'evidence')
                AI_STORY_QA_ALLOW_INPUT = $(if ($EnableInput) { '1' } else { '0' })
            }
        }
    }
}
$path = Join-Path $qaRoot 'gigacode-desktop-mcp.json'
$json = ConvertTo-Json -InputObject $entry -Depth 8
[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "MCP entry created: $path"
Write-Host 'IMPORTANT: Update the existing MCP server entry in GigaCode Desktop!'
Write-Host "Command: $python"
Write-Host "Arguments: -u `"$bootstrap`""
Write-Host 'Transport: STDIO; use the generated cwd/env values from the JSON file.'
Write-Host 'The script does not overwrite GigaCode Desktop settings.'
if (!$EnableInput) { Write-Host 'Read-only mode: rerun with -EnableInput to allow mouse/keyboard controls.' }