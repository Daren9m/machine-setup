# machine-setup

Idempotent Windows 11 developer machine bootstrap script. Safe to re-run — skips anything already installed.

## Quick Start

Run this **one-liner** from an **elevated PowerShell** (Run as Administrator):

```powershell
irm https://raw.githubusercontent.com/Daren9m/machine-setup/main/Install-DevMachine.ps1 | iex
```

To preview what would be installed without making changes:

```powershell
$script = irm https://raw.githubusercontent.com/Daren9m/machine-setup/main/Install-DevMachine.ps1
$scriptBlock = [scriptblock]::Create($script)
& $scriptBlock -DryRun
```

## What It Installs

| Category | Items |
|----------|-------|
| **Directories** | `C:\git` |
| **CLI Tools** (winget) | Git, GitHub CLI, Node.js LTS, PowerShell 7, VS Code, Claude Desktop, Claude Code, GitHub Desktop, Chrome, Firefox, Python 3.13, jq, ripgrep, .NET SDK 10, BIND (dig), Bitwarden, Godot 4 |
| **VS Code Extensions** | PowerShell, GitHub PR, GitLens, Copilot, C#, .NET Runtime, YAML, Prettier, Bicep |
| **Edge Extensions** | Bitwarden, uBlock Origin (opens store page for manual install) |
| **PowerShell Modules** | PSScriptAnalyzer, Pester, Microsoft.Graph, Az, ExchangeOnlineManagement, MicrosoftTeams, SharePoint, PnP.PowerShell, ImportExcel, ScubaGear, Microsoft.Graph.Entra |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-DryRun` | Preview actions without installing |
| `-SkipWinget` | Skip CLI tools |
| `-SkipExtensions` | Skip VS Code and Edge extensions |
| `-SkipModules` | Skip PowerShell modules |
