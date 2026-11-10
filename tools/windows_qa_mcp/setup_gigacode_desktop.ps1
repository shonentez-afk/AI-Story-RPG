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
    & py -3.12 -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.12 is required: install it with py launcher' }
}
$python = Join-Path $venv 'Scripts\python.exe'
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