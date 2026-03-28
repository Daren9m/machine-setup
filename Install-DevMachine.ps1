<#
.SYNOPSIS
    Bootstraps a Windows 11 dev machine with CLI tools, VS Code extensions, and PowerShell modules.
.DESCRIPTION
    Idempotent setup script that installs developer tooling (via winget),
    VS Code extensions, Edge extensions, and M365/Azure PowerShell modules.
    Requires Administrator elevation for machine-wide installs.

    Safe to re-run -- skips anything already installed.
.PARAMETER DryRun
    Preview all actions without installing anything.
.PARAMETER SkipWinget
    Skip winget package installation.
.PARAMETER SkipExtensions
    Skip VS Code extension installation.
.PARAMETER SkipModules
    Skip PowerShell module installation.
.EXAMPLE
    .\Install-DevMachine.ps1
    Install everything on a fresh machine.
.EXAMPLE
    .\Install-DevMachine.ps1 -DryRun
    Preview what would be installed without making changes.
.EXAMPLE
    .\Install-DevMachine.ps1 -SkipModules
    Install CLI tools and VS Code extensions only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$SkipWinget,

    [Parameter()]
    [switch]$SkipExtensions,

    [Parameter()]
    [switch]$SkipModules
)

#region Initialization

$ErrorActionPreference = 'Stop'

if ($DryRun) {
    $WhatIfPreference = $true
}

# Elevation check
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'ERROR: This script requires Administrator privileges.' -ForegroundColor Red
    Write-Host 'Right-click PowerShell and select "Run as Administrator", then re-run this script.' -ForegroundColor Red
    exit 1
}

# Results tracker
$results = @{
    Installed = [System.Collections.Generic.List[string]]::new()
    Skipped   = [System.Collections.Generic.List[string]]::new()
    Failed    = [System.Collections.Generic.List[string]]::new()
}

#endregion Initialization

#region Section 0: Directory Structure

Write-Host "`n=== Directory Structure ===" -ForegroundColor Cyan

$gitRoot = 'C:\git'
if (Test-Path -Path $gitRoot) {
    Write-Host "  $gitRoot : Already exists" -ForegroundColor Green
    $results.Skipped.Add($gitRoot)
}
elseif ($PSCmdlet.ShouldProcess($gitRoot, 'Create directory')) {
    try {
        New-Item -Path $gitRoot -ItemType Directory -Force | Out-Null
        Write-Host "  $gitRoot : Created" -ForegroundColor Green
        $results.Installed.Add($gitRoot)
    }
    catch {
        Write-Host "  $gitRoot : FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed.Add($gitRoot)
    }
}

#endregion Section 0

#region Helper Functions

function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )
    $null -ne (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    [CmdletBinding()]
    param()
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = "$machinePath;$userPath"
}

function Install-WingetPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter()]
        [string]$TestCommand
    )

    # Check if already installed
    if ($TestCommand -and (Test-CommandExists -CommandName $TestCommand)) {
        Write-Host "  $DisplayName : Already installed" -ForegroundColor Green
        $results.Skipped.Add($DisplayName)
        return
    }

    if (-not $TestCommand) {
        $listOutput = winget list --id $PackageId --exact --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $DisplayName : Already installed" -ForegroundColor Green
            $results.Skipped.Add($DisplayName)
            return
        }
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Install via winget ($PackageId)")) {
        return
    }

    Write-Host "  $DisplayName : Installing..." -ForegroundColor Yellow
    try {
        $installArgs = @(
            'install'
            '--id', $PackageId
            '--exact'
            '--accept-source-agreements'
            '--accept-package-agreements'
            '--disable-interactivity'
        )
        & winget @installArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            Write-Host "  $DisplayName : Installed" -ForegroundColor Green
            $results.Installed.Add($DisplayName)
        }
        else {
            Write-Host "  $DisplayName : FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
            $results.Failed.Add($DisplayName)
        }
    }
    catch {
        Write-Host "  $DisplayName : FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed.Add($DisplayName)
    }
}

function Install-PSModule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter()]
        [switch]$AllowPrerelease,

        [Parameter()]
        [switch]$AllowClobber,

        [Parameter()]
        [version]$MinVersion
    )

    $existingModule = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($existingModule) {
        if ($MinVersion -and $existingModule.Version -lt $MinVersion) {
            Write-Host "  $ModuleName : Found v$($existingModule.Version), upgrading to v$MinVersion+..." -ForegroundColor Yellow
        }
        else {
            Write-Host "  $ModuleName : Already installed (v$($existingModule.Version))" -ForegroundColor Green
            $results.Skipped.Add($ModuleName)
            return
        }
    }

    if (-not $PSCmdlet.ShouldProcess($ModuleName, 'Install-Module')) {
        return
    }

    Write-Host "  $ModuleName : Installing..." -ForegroundColor Yellow

    $installParams = @{
        Name               = $ModuleName
        Repository         = 'PSGallery'
        Scope              = 'AllUsers'
        Force              = $true
        SkipPublisherCheck = $true
    }

    if ($AllowPrerelease) {
        $installParams.AllowPrerelease = $true
    }
    if ($AllowClobber) {
        $installParams.AllowClobber = $true
    }

    try {
        Install-Module @installParams
        Write-Host "  $ModuleName : Installed" -ForegroundColor Green
        $results.Installed.Add($ModuleName)
    }
    catch {
        Write-Host "  $ModuleName : FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed.Add($ModuleName)
    }
}

function Install-VSCodeExtension {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ExtensionId
    )

    $installedExtensions = & code --list-extensions 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  $ExtensionId : FAILED - VS Code CLI not available" -ForegroundColor Red
        $results.Failed.Add("ext:$ExtensionId")
        return
    }

    $isInstalled = $installedExtensions | Where-Object {
        $_ -eq $ExtensionId
    }

    if ($isInstalled) {
        Write-Host "  $ExtensionId : Already installed" -ForegroundColor Green
        $results.Skipped.Add("ext:$ExtensionId")
        return
    }

    if (-not $PSCmdlet.ShouldProcess($ExtensionId, 'Install VS Code extension')) {
        return
    }

    Write-Host "  $ExtensionId : Installing..." -ForegroundColor Yellow
    try {
        & code --install-extension $ExtensionId --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $ExtensionId : Installed" -ForegroundColor Green
            $results.Installed.Add("ext:$ExtensionId")
        }
        else {
            Write-Host "  $ExtensionId : FAILED" -ForegroundColor Red
            $results.Failed.Add("ext:$ExtensionId")
        }
    }
    catch {
        Write-Host "  $ExtensionId : FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed.Add("ext:$ExtensionId")
    }
}

#endregion Helper Functions

#region Data Definitions

$wingetPackages = @(
    @{ PackageId = 'Git.Git';                    DisplayName = 'Git';               TestCommand = 'git' }
    @{ PackageId = 'GitHub.cli';                 DisplayName = 'GitHub CLI';         TestCommand = 'gh' }
    @{ PackageId = 'OpenJS.NodeJS.LTS';          DisplayName = 'Node.js LTS';       TestCommand = 'node' }
    @{ PackageId = 'Microsoft.PowerShell';       DisplayName = 'PowerShell 7';      TestCommand = 'pwsh' }
    @{ PackageId = 'Microsoft.VisualStudioCode'; DisplayName = 'Visual Studio Code'; TestCommand = 'code' }
    @{ PackageId = 'Anthropic.Claude';           DisplayName = 'Claude Desktop';    TestCommand = '' }
    @{ PackageId = 'Anthropic.ClaudeCode';       DisplayName = 'Claude Code';       TestCommand = 'claude' }
    @{ PackageId = 'GitHub.GitHubDesktop';       DisplayName = 'GitHub Desktop';    TestCommand = '' }
    @{ PackageId = 'Google.Chrome';              DisplayName = 'Google Chrome';     TestCommand = '' }
    @{ PackageId = 'Mozilla.Firefox';            DisplayName = 'Firefox';           TestCommand = '' }
    @{ PackageId = 'Python.Python.3.13';         DisplayName = 'Python 3.13';       TestCommand = 'python' }
    @{ PackageId = 'jqlang.jq';                  DisplayName = 'jq';                TestCommand = 'jq' }
    @{ PackageId = 'BurntSushi.ripgrep.MSVC';    DisplayName = 'ripgrep';           TestCommand = 'rg' }
    @{ PackageId = 'Microsoft.DotNet.SDK.10';    DisplayName = '.NET SDK 10';       TestCommand = '' }
    @{ PackageId = 'ISC.Bind';                   DisplayName = 'BIND (dig)';        TestCommand = 'dig' }
    @{ PackageId = 'Bitwarden.Bitwarden';        DisplayName = 'Bitwarden';         TestCommand = '' }
    @{ PackageId = 'GodotEngine.GodotEngine';    DisplayName = 'Godot 4';           TestCommand = '' }
)

$vsCodeExtensions = @(
    'ms-vscode.powershell'
    'github.vscode-pull-request-github'
    'eamodio.gitlens'
    'github.copilot'
    'ms-dotnettools.csharp'
    'ms-dotnettools.vscode-dotnet-runtime'
    'redhat.vscode-yaml'
    'esbenp.prettier-vscode'
    'ms-azuretools.vscode-bicep'
)

$psModules = @(
    @{ Name = 'PSScriptAnalyzer' }
    @{ Name = 'Pester';                                AllowClobber = $true; MinVersion = '5.0.0' }
    @{ Name = 'Microsoft.Graph' }
    @{ Name = 'Az';                                    AllowClobber = $true }
    @{ Name = 'ExchangeOnlineManagement' }
    @{ Name = 'MicrosoftTeams' }
    @{ Name = 'Microsoft.Online.SharePoint.PowerShell' }
    @{ Name = 'PnP.PowerShell' }
    @{ Name = 'ImportExcel' }
    @{ Name = 'ScubaGear' }
    @{ Name = 'Microsoft.Graph.Entra';                 AllowPrerelease = $true }
)

#endregion Data Definitions

#region Section 1: Winget Packages

if (-not $SkipWinget) {
    Write-Host "`n=== CLI Tools (winget) ===" -ForegroundColor Cyan

    if (-not (Test-CommandExists -CommandName 'winget')) {
        Write-Host '  winget not found. Attempting to register App Installer...' -ForegroundColor Yellow
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
        }
        catch {
            Write-Host '  ERROR: Could not register App Installer.' -ForegroundColor Red
        }

        if (-not (Test-CommandExists -CommandName 'winget')) {
            Write-Host '  ERROR: winget is not available. Install "App Installer" from the Microsoft Store.' -ForegroundColor Red
            Write-Host '  Skipping winget section.' -ForegroundColor Red
        }
    }

    if (Test-CommandExists -CommandName 'winget') {
        foreach ($pkg in $wingetPackages) {
            $splatArgs = @{
                PackageId   = $pkg.PackageId
                DisplayName = $pkg.DisplayName
            }
            if ($pkg.TestCommand) {
                $splatArgs.TestCommand = $pkg.TestCommand
            }
            Install-WingetPackage @splatArgs
        }

        Write-Host "`n  Refreshing PATH..." -ForegroundColor DarkGray
        Update-SessionPath
    }
}

#endregion Section 1

#region Section 2: VS Code Extensions

if (-not $SkipExtensions) {
    Write-Host "`n=== VS Code Extensions ===" -ForegroundColor Cyan

    if (-not (Test-CommandExists -CommandName 'code')) {
        Write-Host '  VS Code CLI not found. Install VS Code first (included in winget section).' -ForegroundColor Red
        $results.Failed.Add('VS Code extensions (code CLI not available)')
    }
    else {
        foreach ($extId in $vsCodeExtensions) {
            Install-VSCodeExtension -ExtensionId $extId
        }
    }
}

#endregion Section 2

#region Section 2b: Edge Extensions

if (-not $SkipExtensions) {
    Write-Host "`n=== Edge Extensions (manual install) ===" -ForegroundColor Cyan

    $edgeExtensions = @(
        @{
            Name = 'Bitwarden'
            Url  = 'https://microsoftedge.microsoft.com/addons/detail/bitwarden-password-manage/jbkfoedolllekgbhcbcoahefnbanhhlh'
        }
        @{
            Name = 'uBlock Origin'
            Url  = 'https://microsoftedge.microsoft.com/addons/detail/ublock-origin/odfafepnkmbhccpbejgmiehpchacaeak'
        }
    )

    foreach ($ext in $edgeExtensions) {
        if ($PSCmdlet.ShouldProcess($ext.Name, 'Open Edge Add-ons page')) {
            Write-Host "  $($ext.Name): Opening Edge Add-ons page..." -ForegroundColor Yellow
            Start-Process $ext.Url
        }
    }

    Write-Host '  NOTE: Edge extensions require manual "Get" click in the browser.' -ForegroundColor DarkYellow
}

#endregion Section 2b

#region Section 3: PowerShell Modules

if (-not $SkipModules) {
    Write-Host "`n=== PowerShell Modules ===" -ForegroundColor Cyan

    # Bootstrap NuGet provider and trust PSGallery
    Write-Host '  Checking NuGet provider...' -ForegroundColor DarkGray
    $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nugetProvider -or $nugetProvider.Version -lt [version]'2.8.5.201') {
        if ($PSCmdlet.ShouldProcess('NuGet', 'Install package provider')) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            Write-Host '  NuGet provider: Installed' -ForegroundColor Green
        }
    }

    $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
        if ($PSCmdlet.ShouldProcess('PSGallery', 'Set as Trusted repository')) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            Write-Host '  PSGallery: Set as Trusted' -ForegroundColor Green
        }
    }

    Write-Host '' # blank line before module list

    foreach ($mod in $psModules) {
        $splatArgs = @{ ModuleName = $mod.Name }
        if ($mod.AllowPrerelease) {
            $splatArgs.AllowPrerelease = $true
        }
        if ($mod.AllowClobber) {
            $splatArgs.AllowClobber = $true
        }
        if ($mod.MinVersion) {
            $splatArgs.MinVersion = [version]$mod.MinVersion
        }

        if ($mod.Name -eq 'Microsoft.Graph') {
            Write-Host '  Microsoft.Graph: This is a large module -- install may take several minutes...' -ForegroundColor DarkGray
        }
        if ($mod.Name -eq 'Az') {
            Write-Host '  Az: This is a large module -- install may take several minutes...' -ForegroundColor DarkGray
        }

        Install-PSModule @splatArgs

        if ($mod.Name -eq 'ScubaGear') {
            Write-Host '  NOTE: Run "Initialize-SCuBA" after import to download OPA and verify dependencies.' -ForegroundColor DarkYellow
        }
        if ($mod.Name -eq 'Microsoft.Graph.Entra') {
            Write-Host '  NOTE: Microsoft.Graph.Entra is a prerelease module.' -ForegroundColor DarkYellow
        }
    }
}

#endregion Section 3

#region Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host '  Bootstrap Summary' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$installedColor = if ($results.Installed.Count -gt 0) { 'Green' } else { 'DarkGray' }
$failedColor = if ($results.Failed.Count -gt 0) { 'Red' } else { 'Green' }

Write-Host "  Installed : $($results.Installed.Count)" -ForegroundColor $installedColor
Write-Host "  Skipped   : $($results.Skipped.Count) (already present)" -ForegroundColor DarkGray
Write-Host "  Failed    : $($results.Failed.Count)" -ForegroundColor $failedColor

if ($results.Failed.Count -gt 0) {
    Write-Host "`n  Failed items:" -ForegroundColor Red
    foreach ($item in $results.Failed) {
        Write-Host "    - $item" -ForegroundColor Red
    }
}

Write-Host "`n  Post-install reminders:" -ForegroundColor Yellow
Write-Host '    1. Restart your terminal to pick up PATH changes' -ForegroundColor Yellow
Write-Host '    2. Run "Initialize-SCuBA" if you installed ScubaGear' -ForegroundColor Yellow
Write-Host '    3. Run "gh auth login" to authenticate GitHub CLI' -ForegroundColor Yellow
Write-Host ''

#endregion Summary
