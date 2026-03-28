# Cloud Dev Machine Additions — Design Spec

## Context

The `Install-DevMachine.ps1` script bootstraps Windows 11 developer machines with CLI tools, VS Code extensions, and PowerShell modules. It's heavily oriented toward Microsoft 365/Azure admin-developer workloads but lacks several essentials for **cloud development on Azure VMs and Dev Box environments**.

This spec adds cloud-native dev tooling while preserving the script's idempotent, single-file, one-liner-deployable architecture.

## Additions

### New Winget Packages (always installed)

| PackageId | DisplayName | TestCommand | Why |
|-----------|-------------|-------------|-----|
| `Microsoft.AzureCLI` | Azure CLI | `az` | Core Azure CLI — used in docs, CI/CD, and alongside Az PS module |
| `Hashicorp.Terraform` | Terraform | `terraform` | Dominant IaC tool, complements Bicep for multi-cloud |
| `Microsoft.Azure.DataStudio` | Azure Data Studio | `""` | Lightweight SQL/Postgres database tool |
| `Microsoft.WindowsTerminal` | Windows Terminal | `wt` | Modern terminal — usually pre-installed on Win11 but ensures availability |
| `Microsoft.Sysinternals.Suite` | Sysinternals Suite | `""` | Process Explorer, ProcMon, TCPView — essential Windows diagnostics |

### New Winget Packages (optional — `-IncludeDocker` switch)

| PackageId | DisplayName | TestCommand | Why |
|-----------|-------------|-------------|-----|
| `Docker.DockerDesktop` | Docker Desktop | `docker` | Container development — requires nested virtualization |

### WSL 2 (optional — `-IncludeDocker` switch)

- Install via `wsl --install --no-distribution` (enables WSL 2 feature without downloading a distro)
- Prerequisite for Docker Desktop on Windows
- **Constraint**: Requires nested virtualization — not available on all Azure VM SKUs or Windows 365 Cloud PCs
- Idempotent check: `wsl --status` to detect if already enabled

### New VS Code Extensions

| Extension ID | Name | Conditional |
|-------------|------|-------------|
| `hashicorp.terraform` | HashiCorp Terraform | Always |
| `ms-vscode.vscode-node-azure-pack` | Azure Tools | Always |
| `ms-azuretools.vscode-docker` | Docker | Only with `-IncludeDocker` |

### New PowerShell Modules

| Module | Notes |
|--------|-------|
| `InformationProtection` | Microsoft Information Protection (MIP) cmdlets for Purview compliance |

### MIP SDK

- Install `Microsoft.InformationProtection.File` NuGet package via `Install-Package` from the NuGet provider
- This provides the .NET MIP SDK binaries for building apps that apply sensitivity labels
- Idempotent check: `Get-Package -Name 'Microsoft.InformationProtection.File' -ErrorAction SilentlyContinue`

## Script Changes

### New Parameter

```powershell
[Parameter()]
[switch]$IncludeDocker
```

Added to existing `param()` block. Comment-based help updated with new parameter description and example.

### Data Definitions

- Append 5 new entries to `$wingetPackages` array
- Append 2 new entries to `$vsCodeExtensions` array
- Append 1 new entry to `$psModules` array
- New `$dockerPackages` array (1 entry) — only processed when `-IncludeDocker` is set
- New `$dockerExtensions` array (1 entry) — only processed when `-IncludeDocker` is set

### New Section: Docker & WSL 2 (conditional)

After the main winget section, add a new region:

```
#region Section 1b: Docker & WSL 2 (optional)
if ($IncludeDocker) {
    # 1. Enable WSL 2 if not already present
    # 2. Install Docker Desktop via winget
    # 3. Install Docker VS Code extension
}
#endregion
```

### README Updates

- Add new tools to the feature list
- Document `-IncludeDocker` switch
- Add note about nested virtualization requirement for cloud VMs
- Update one-liner examples

## What We Are NOT Changing

- Script remains a single `.ps1` file
- No new dependencies or external scripts
- Existing `-Skip*` switches continue to work as before
- `-SkipWinget` skips the new winget packages too (including Docker even if `-IncludeDocker` is set)
- No changes to helper functions — they already handle the patterns needed

## Verification

1. **Dry run**: `.\Install-DevMachine.ps1 -DryRun` — verify new packages appear in WhatIf output
2. **Dry run with Docker**: `.\Install-DevMachine.ps1 -DryRun -IncludeDocker` — verify Docker/WSL items appear
3. **Idempotent re-run**: Run twice — second run should skip all already-installed items
4. **Skip flags**: `-SkipWinget` should skip all new winget packages; `-SkipExtensions` should skip new VS Code extensions
5. **README**: Verify documentation matches actual behavior
