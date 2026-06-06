#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Block', 'Unblock', 'List', 'Menu')]
    [string]$Action = 'Menu',

    [Parameter(Position = 1)]
    [Alias('Program', 'Programs')]
    [string[]]$Path,

    [string]$Group = 'App Network Blocker',

    [switch]$Inbound,

    [switch]$Recurse,

    [switch]$All
)

Set-StrictMode -Version 2.0

$Script:ExecutableExtensions = @('.exe', '.com', '.scr')

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-NetSecurityAvailable {
    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        throw 'Windows Firewall PowerShell cmdlets were not found. Run this on Windows 10/11 or Windows Server.'
    }
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'Creating or deleting firewall rules requires Administrator. Right-click PowerShell or Run-AppNetworkBlocker.bat and choose Run as administrator.'
    }
}

function Resolve-AppTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$InputPath,

        [switch]$Recurse
    )

    $targets = foreach ($candidate in $InputPath) {
        $trimmed = $candidate.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
            ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
            $trimmed = $trimmed.Substring(1, $trimmed.Length - 2)
        }

        $item = Get-Item -LiteralPath $trimmed -ErrorAction Stop
        if ($item.PSIsContainer) {
            $search = @{
                LiteralPath = $item.FullName
                File        = $true
                ErrorAction = 'SilentlyContinue'
            }

            if ($Recurse) {
                $search.Recurse = $true
            }

            $programs = @(
                Get-ChildItem @search |
                    Where-Object { $Script:ExecutableExtensions -contains $_.Extension.ToLowerInvariant() }
            )

            if ($programs.Count -eq 0) {
                Write-Warning "No executable targets found in folder: $($item.FullName)"
                continue
            }

            Write-Host "Scanned folder: $($item.FullName); found $($programs.Count) executable target(s)."
            $programs | ForEach-Object { $_.FullName }
            continue
        }

        if ($Script:ExecutableExtensions -notcontains $item.Extension.ToLowerInvariant()) {
            Write-Warning "This path is not a common executable file type: $($item.FullName)"
        }

        $item.FullName
    }

    return @($targets | Sort-Object -Unique)
}

function Get-ProgramHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath
    )

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($ProgramPath.ToLowerInvariant())
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes[0..7] | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $sha.Dispose()
    }
}

function Get-RuleName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Outbound', 'Inbound')]
        [string]$Direction
    )

    $hash = Get-ProgramHash -ProgramPath $ProgramPath
    return "ANB-$hash-$Direction"
}

function Get-RuleDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Outbound', 'Inbound')]
        [string]$Direction
    )

    $fileName = Split-Path -Leaf $ProgramPath
    return "Block Internet - $fileName - $Direction"
}

function Get-TargetDirections {
    param([switch]$IncludeInbound)

    $directions = @('Outbound')
    if ($IncludeInbound) {
        $directions += 'Inbound'
    }

    return $directions
}

function New-AppBlockRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Outbound', 'Inbound')]
        [string]$Direction
    )

    $ruleName = Get-RuleName -ProgramPath $ProgramPath -Direction $Direction
    $displayName = Get-RuleDisplayName -ProgramPath $ProgramPath -Direction $Direction
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if ($existing) {
        if ($PSCmdlet.ShouldProcess($ProgramPath, "enable existing $Direction block rule")) {
            Set-NetFirewallRule -Name $ruleName -Enabled True -Action Block -Profile Any | Out-Null
        }
        Write-Host "Already exists and enabled: $displayName"
        return
    }

    if ($PSCmdlet.ShouldProcess($ProgramPath, "create $Direction block rule")) {
        New-NetFirewallRule `
            -Name $ruleName `
            -DisplayName $displayName `
            -Description "Created by AppNetworkBlocker.ps1 for $ProgramPath" `
            -Group $Group `
            -Direction $Direction `
            -Program $ProgramPath `
            -Action Block `
            -Profile Any `
            -Enabled True | Out-Null
    }

    Write-Host "Created: $displayName"
}

function Remove-AppBlockRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath
    )

    foreach ($direction in @('Outbound', 'Inbound')) {
        $ruleName = Get-RuleName -ProgramPath $ProgramPath -Direction $direction
        $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

        if (-not $rule) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($ProgramPath, "remove $direction block rule")) {
            Remove-NetFirewallRule -Name $ruleName
        }

        Write-Host "Removed: $(Get-RuleDisplayName -ProgramPath $ProgramPath -Direction $direction)"
    }
}

function Remove-AllAppBlockRules {
    $rules = @(Get-NetFirewallRule -Group $Group -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0) {
        Write-Host 'No rules created by this tool were found.'
        return
    }

    foreach ($rule in $rules) {
        if ($PSCmdlet.ShouldProcess($rule.DisplayName, 'remove firewall rule')) {
            Remove-NetFirewallRule -Name $rule.Name
        }
        Write-Host "Removed: $($rule.DisplayName)"
    }
}

function Get-AppBlockRules {
    $rules = @(Get-NetFirewallRule -Group $Group -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0) {
        Write-Host 'No rules created by this tool were found.'
        return
    }

    $rules |
        Sort-Object Direction, DisplayName |
        ForEach-Object {
            $appFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue
            [pscustomobject]@{
                Enabled     = $_.Enabled
                Direction   = $_.Direction
                Action      = $_.Action
                Program     = $appFilter.Program
                DisplayName = $_.DisplayName
            }
        } |
        Format-Table -AutoSize
}

function Split-MenuPaths {
    param([string]$RawText)

    return @(
        $RawText -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Invoke-Block {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProgramPaths,

        [switch]$IncludeInbound,

        [switch]$Recurse
    )

    Assert-Administrator

    $resolvedPrograms = Resolve-AppTargets -InputPath $ProgramPaths -Recurse:$Recurse
    if ($resolvedPrograms.Count -eq 0) {
        throw 'No executable targets were found for firewall rule creation.'
    }

    foreach ($resolved in $resolvedPrograms) {
        foreach ($direction in (Get-TargetDirections -IncludeInbound:$IncludeInbound)) {
            New-AppBlockRule -ProgramPath $resolved -Direction $direction
        }
    }
}

function Invoke-Unblock {
    param(
        [string[]]$ProgramPaths,

        [switch]$Recurse,

        [switch]$RemoveAll
    )

    Assert-Administrator

    if ($RemoveAll) {
        Remove-AllAppBlockRules
        return
    }

    if (-not $ProgramPaths -or $ProgramPaths.Count -eq 0) {
        throw 'Provide program/folder paths to unblock, or use -All to delete all rules created by this tool.'
    }

    $resolvedPrograms = Resolve-AppTargets -InputPath $ProgramPaths -Recurse:$Recurse
    if ($resolvedPrograms.Count -eq 0) {
        throw 'No executable targets were found for firewall rule removal.'
    }

    foreach ($resolved in $resolvedPrograms) {
        Remove-AppBlockRule -ProgramPath $resolved
    }
}

function Read-RecurseChoice {
    $raw = Read-Host 'Scan subfolders too? Enter Y for recursive scan, or press Enter for current folder only'
    return ($raw -match '^(y|yes)$')
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host 'App Network Blocker'
        Write-Host '1. Block program/folder network access (outbound only, recommended)'
        Write-Host '2. Block program/folder network access (outbound + inbound)'
        Write-Host '3. List rules created by this tool'
        Write-Host '4. Unblock program/folder'
        Write-Host '5. Delete all rules created by this tool'
        Write-Host '0. Exit'
        Write-Host ''

        $choice = Read-Host 'Choose'
        switch ($choice) {
            '1' {
                $raw = Read-Host 'Enter full program or folder path; separate multiple paths with semicolons'
                $scanRecurse = Read-RecurseChoice
                Invoke-Block -ProgramPaths (Split-MenuPaths -RawText $raw) -Recurse:$scanRecurse
            }
            '2' {
                $raw = Read-Host 'Enter full program or folder path; separate multiple paths with semicolons'
                $scanRecurse = Read-RecurseChoice
                Invoke-Block -ProgramPaths (Split-MenuPaths -RawText $raw) -IncludeInbound -Recurse:$scanRecurse
            }
            '3' {
                Get-AppBlockRules
            }
            '4' {
                $raw = Read-Host 'Enter full program or folder path to unblock; separate multiple paths with semicolons'
                $scanRecurse = Read-RecurseChoice
                Invoke-Unblock -ProgramPaths (Split-MenuPaths -RawText $raw) -Recurse:$scanRecurse
            }
            '5' {
                $confirm = Read-Host 'Delete all rules created by this tool? Type YES to continue'
                if ($confirm -eq 'YES') {
                    Invoke-Unblock -RemoveAll
                }
            }
            '0' {
                return
            }
            default {
                Write-Host 'Invalid choice. Try again.'
            }
        }
    }
}

Assert-NetSecurityAvailable

switch ($Action) {
    'Block' {
        if (-not $Path -or $Path.Count -eq 0) {
            throw 'Provide a program or folder path, for example: .\AppNetworkBlocker.ps1 Block "C:\Path\App.exe"'
        }
        Invoke-Block -ProgramPaths $Path -IncludeInbound:$Inbound -Recurse:$Recurse
    }
    'Unblock' {
        Invoke-Unblock -ProgramPaths $Path -Recurse:$Recurse -RemoveAll:$All
    }
    'List' {
        Get-AppBlockRules
    }
    'Menu' {
        Show-Menu
    }
}
