# AI Story RPG Windows QA MCP - native GigaCode Desktop (NO Cline).
# Example: .\tools\windows_qa_mcp\setup_gigacode_desktop.ps1 -AppExe 'D:\Games\AI-Story-RPG-Windows\ai_story_reader.exe'
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
    # The Windows Python launcher can have Python 3.13/3.14 installed but not 3.12.
    # Probe the actual default interpreter instead of demanding one minor version.
    $launcher = $null
    foreach ($candidate in @('py', 'python')) {
        if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
        try {
            $reported = (& $candidate -c 'import sys; print("{}.{}".format(sys.version_info.major, sys.version_info.minor))' 2>$null | Select-Object -Last 1)
            if ($LASTEXITCODE -ne 0 -or -not $reported) { continue }
            $detected = [version]([string]$reported).Trim()
            if ($detected -ge [version]'3.12') {
                $launcher = $candidate
                Write-Host "Creating QA environment using $candidate (Python $detected)"
                break
            }
        } catch {
            # Try the other common Python entrypoint if this launcher is unavailable.
        }
    }
    if (-not $launcher) { throw 'Python 3.12+ not found through py or python. Check: py --version; python --version; py -0p' }
    & $launcher -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create MCP virtual environment using installed Python' }
}
$python = Join-Path $venv 'Scripts\python.exe'
# Do not silently reuse a stale virtual environment created by Python 3.11.
& $python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'QA virtual environment requires Python 3.12+. Remove only %LOCALAPPDATA%\AIStoryRPG-QA\python if it contains an old Python and rerun setup' }
& $python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Could not install Python MCP dependencies' }
$entry = @{
    mcpServers = @{
        'ai-story-rpg-windows-qa' = @{
            command = $python
            args    = @('-m', 'tools.windows_qa_mcp.server')
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
Write-Host 'GigaCode Desktop -> Settings -> MCP -> Add -> Local (STDIO); copy the generated command/args/cwd/env.'
Write-Host 'This script deliberately does not overwrite your GigaCode settings.'
if (!$EnableInput) { Write-Host 'Read-only mode: restart with -EnableInput to allow clicking and typing.' }
& $python -m tools.windows_qa_mcp.server --self-check
if ($LASTEXITCODE -ne 0) { throw 'MCP preflight failed' }