# ==========================================
# Omega Winget Bootstrap (Optimized)
# Personal provisioning tool to bootstrap a fresh Windows environment
# using winget, category selection, and reproducible configs.
#
# Optimized variant: batches winget status queries (one `winget list`
# and one `winget upgrade` call total instead of two per app) and adds
# hardened error handling / path resolution.
#
# Usage:
#   .\omega-winget-bootstrap.optimized.ps1 [-DryRun] [-Update] [-Snapshot] [-SnapshotPath <path>] [-ConfigFile <path>]
#
# -Snapshot scans currently-installed winget apps and writes apps-omega.json
# (category-keyed, same shape as apps.json). Once apps-omega.json exists,
# normal runs auto-load it instead of apps.json - pass -ConfigFile apps.json
# to opt back into the general list.
#
# Recommended launch:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\omega-winget-bootstrap.optimized.ps1
# ==========================================

param(
    [switch]$DryRun,
    [switch]$Update,
    [switch]$Snapshot,
    [string]$SnapshotPath = "apps-omega.json",
    [string]$ConfigFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==========================================
# Global Update Mode
# ==========================================

if ($Update) {
    Write-Host ""
    Write-Host "Updating all installed applications..." -ForegroundColor Cyan
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
    Write-Host "Done." -ForegroundColor Green
    exit
}

# ==========================================
# Batched App Status (single winget list / winget upgrade call)
# ==========================================
# Defined early (before Snapshot Mode / Load Config) since -Snapshot needs
# these before the rest of the script's functions are reached.

# Parses "Name  Id  Version  ..." winget table output into a map of
# Id -> Name. Matches the Id as a whitespace-bounded token so an Id that is
# a substring of another Id's line can't produce a false match.
function ConvertFrom-WingetTable {
    param([string[]]$RawOutput)

    $map = @{}
    if (-not $RawOutput) {
        return $map
    }

    foreach ($line in $RawOutput) {
        if ($line -notmatch '^\S') {
            continue
        }
        # Winget columns are separated by 2+ spaces.
        $cols = [regex]::Split($line.TrimEnd(), '\s{2,}')
        if ($cols.Count -lt 2) {
            continue
        }

        # Find the column that looks like a winget package Id (contains a dot,
        # no spaces) - this is more reliable than assuming a fixed column index
        # since header/separator rows and localized columns vary.
        for ($c = 1; $c -lt $cols.Count; $c++) {
            $candidate = $cols[$c].Trim()
            if ($candidate -match '^[\w.+-]+\.[\w.+-]+$') {
                $name = $cols[0].Trim().TrimEnd('.')
                if ($name.Length -gt 0 -and -not $map.ContainsKey($candidate)) {
                    $map[$candidate] = $name
                }
                break
            }
        }
    }

    return $map
}

function Get-WingetStatusMaps {
    Write-Host "Querying winget (list + upgrade) - one batch call each..." -ForegroundColor DarkGray

    $listRaw = winget list --accept-source-agreements 2>$null
    $upgradeRaw = winget upgrade --accept-source-agreements 2>$null

    $installedMap = ConvertFrom-WingetTable $listRaw
    $upgradeMap   = ConvertFrom-WingetTable $upgradeRaw

    return @{
        Installed = $installedMap
        Upgradable = $upgradeMap
    }
}

# `winget list` table-scraping (ConvertFrom-WingetTable) can misdetect a
# Version column as the Id when a row has no real Id (unknown source, or
# a non-winget-catalog package), polluting output with garbage like
# "1.2.3". `winget export` returns only real, reinstallable PackageIdentifiers,
# so it's the reliable source for -Snapshot's list of installed app ids.
function Get-InstalledPackageIds {
    $exportPath = Join-Path ([System.IO.Path]::GetTempPath()) "omega-winget-export-$([guid]::NewGuid()).json"
    try {
        winget export -o $exportPath --accept-source-agreements 2>$null | Out-Null
        if (-not (Test-Path $exportPath)) {
            return @()
        }
        $exportData = Get-Content $exportPath -Raw | ConvertFrom-Json
        $ids = @()
        foreach ($source in @($exportData.Sources)) {
            # Only the winget catalog source is reinstallable via
            # `winget install --id X -e` (no -s flag). Skip other sources
            # (e.g. msstore) whose ids need a source-specific install.
            $sourceArg = $source.SourceDetails.Argument
            if ($sourceArg -notmatch 'winget\.microsoft\.com') {
                continue
            }
            foreach ($pkg in @($source.Packages)) {
                $ids += $pkg.PackageIdentifier
            }
        }
        return @($ids | Sort-Object -Unique)
    } finally {
        if (Test-Path $exportPath) {
            Remove-Item $exportPath -Force
        }
    }
}

# ==========================================
# Snapshot Mode
# ==========================================
# Scans what's actually installed via winget and writes a category-keyed
# json file (same shape as apps.json). Apps already present in apps.json
# keep their category; anything installed but not curated there lands in
# "Uncategorized" so the snapshot never silently drops apps.

if ($Snapshot) {
    $wingetVersion = winget --version 2>$null
    if (-not $wingetVersion) {
        Write-Host "ERROR: winget not found. Install App Installer from the Microsoft Store." -ForegroundColor Red
        exit 1
    }

    Write-Host "Exporting installed package list via winget export..." -ForegroundColor DarkGray
    $installedIds = @(Get-InstalledPackageIds)

    $referencePath = Join-Path $PSScriptRoot "apps.json"
    $reference = $null
    if (Test-Path $referencePath) {
        try {
            $reference = Get-Content $referencePath -Raw | ConvertFrom-Json
        } catch {
            Write-Host "WARNING: Failed to parse apps.json for categorization - all installed apps will be Uncategorized." -ForegroundColor DarkYellow
            $reference = $null
        }
    }

    $snapshotData = [ordered]@{}
    $claimed = New-Object System.Collections.Generic.HashSet[string]

    if ($reference) {
        foreach ($cat in ($reference.PSObject.Properties | Select-Object -ExpandProperty Name)) {
            $catIds = @(@($reference.$cat) | Where-Object { $installedIds -contains $_ } | Sort-Object -Unique)
            foreach ($id in $catIds) {
                [void]$claimed.Add($id)
            }
            if ($catIds.Count -gt 0) {
                $snapshotData[$cat] = @($catIds)
            }
        }
    }

    $uncategorized = @($installedIds | Where-Object { -not $claimed.Contains($_) } | Sort-Object -Unique)
    if ($uncategorized.Count -gt 0) {
        $snapshotData["Uncategorized"] = $uncategorized
    }

    $outPath = $SnapshotPath
    if (-not [System.IO.Path]::IsPathRooted($outPath)) {
        $outPath = Join-Path $PSScriptRoot $outPath
    }

    $snapshotData | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8

    Write-Host ""
    Write-Host "Snapshot written to $outPath" -ForegroundColor Green
    Write-Host ("  Categories    : {0}" -f $snapshotData.Keys.Count) -ForegroundColor DarkGray
    Write-Host ("  Apps captured : {0}" -f $installedIds.Count) -ForegroundColor DarkGray
    Write-Host ("  Uncategorized : {0}" -f $uncategorized.Count) -ForegroundColor DarkGray
    exit 0
}

# ==========================================
# Load Config
# ==========================================

if (-not $ConfigFile) {
    $snapshotCandidate = Join-Path $PSScriptRoot "apps-omega.json"
    if (Test-Path $snapshotCandidate) {
        $ConfigFile = "apps-omega.json"
        Write-Host "Using existing snapshot: apps-omega.json" -ForegroundColor DarkGray
    } else {
        $ConfigFile = "apps.json"
    }
}

$configPath = $ConfigFile
if (-not [System.IO.Path]::IsPathRooted($configPath)) {
    $configPath = Join-Path $PSScriptRoot $ConfigFile
}

if (!(Test-Path $configPath)) {
    Write-Host "ERROR: config file not found at $configPath" -ForegroundColor Red
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to parse $ConfigFile - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ==========================================
# Helpers
# ==========================================

function Remove-Duplicates {
    param($AppList)
    return @($AppList | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique)
}

function Get-ConfigCategories {
    return $config.PSObject.Properties | Select-Object -ExpandProperty Name
}

# ==========================================
# Category Selection Menu
# ==========================================

function Show-CategoryMenu {
    $categories = @(Get-ConfigCategories)
    $total = $categories.Count

    $selected = @{}
    foreach ($cat in $categories) {
        $selected[$cat] = $false
    }

    $presets = @{}
    $presets["1"] = @{ Name = "Core Setup";  Cats = @("RuntimesAndDrivers", "CoreSystem") }
    $presets["2"] = @{ Name = "Dev";         Cats = @("RuntimesAndDrivers", "CoreSystem", "Development", "Networking") }
    $presets["3"] = @{ Name = "Gaming";      Cats = @("RuntimesAndDrivers", "CoreSystem", "Gaming", "Downloads", "Peripherals") }
    $presets["4"] = @{ Name = "Streaming";   Cats = @("RuntimesAndDrivers", "CoreSystem", "Streaming", "Media") }
    $presets["5"] = @{ Name = "Full";        Cats = @() }

    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  Omega Winget Bootstrap (Optimized)" -ForegroundColor Cyan
        Write-Host "  Select categories to install:" -ForegroundColor DarkGray
        Write-Host ""

        $i = 1
        foreach ($cat in $categories) {
            if ($selected[$cat]) {
                $mark = "[X]"
                $color = "Green"
            } else {
                $mark = "[ ]"
                $color = "DarkGray"
            }
            Write-Host ("  {0,2})  {1}  {2}" -f $i, $mark, $cat) -ForegroundColor $color
            $i++
        }

        Write-Host ""
        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
        Write-Host "   P)  Load preset" -ForegroundColor Yellow
        Write-Host "   A)  Select all" -ForegroundColor Yellow
        Write-Host "   C)  Clear all" -ForegroundColor Yellow
        Write-Host "   Q)  Confirm and continue" -ForegroundColor Cyan
        Write-Host ""

        $selectedNames = @()
        foreach ($cat in $categories) {
            if ($selected[$cat]) {
                $selectedNames += $cat
            }
        }

        if ($selectedNames.Count -gt 0) {
            $selLine = $selectedNames -join ", "
            Write-Host "  Selected: $selLine" -ForegroundColor Cyan
        } else {
            Write-Host "  Selected: (none)" -ForegroundColor DarkGray
        }

        Write-Host ""
        $rawInput = Read-Host "  Enter number, or command"
        $rawInput = $rawInput.Trim().ToUpper()

        if ($rawInput -eq "Q") {
            if ($selectedNames.Count -eq 0) {
                Write-Host "  No categories selected. Please select at least one." -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }
            return $selectedNames
        }

        if ($rawInput -eq "A") {
            foreach ($cat in $categories) {
                $selected[$cat] = $true
            }
            continue
        }

        if ($rawInput -eq "C") {
            foreach ($cat in $categories) {
                $selected[$cat] = $false
            }
            continue
        }

        if ($rawInput -eq "P") {
            Clear-Host
            Write-Host ""
            Write-Host "  Load a preset:" -ForegroundColor Cyan
            Write-Host ""
            foreach ($key in ($presets.Keys | Sort-Object)) {
                $pName = $presets[$key].Name
                if ($presets[$key].Cats.Count -eq 0) {
                    Write-Host ("  {0})  {1}  (all categories)" -f $key, $pName) -ForegroundColor Yellow
                } else {
                    $catList = $presets[$key].Cats -join ", "
                    Write-Host ("  {0})  {1}  [{2}]" -f $key, $pName, $catList) -ForegroundColor Yellow
                }
            }
            Write-Host ""
            $presetChoice = Read-Host "  Enter preset number (or Enter to cancel)"
            $presetChoice = $presetChoice.Trim()

            if ($presets.ContainsKey($presetChoice)) {
                foreach ($cat in $categories) {
                    $selected[$cat] = $false
                }
                if ($presets[$presetChoice].Cats.Count -eq 0) {
                    foreach ($cat in $categories) {
                        $selected[$cat] = $true
                    }
                } else {
                    foreach ($cat in $presets[$presetChoice].Cats) {
                        if ($selected.ContainsKey($cat)) {
                            $selected[$cat] = $true
                        }
                    }
                }
            }
            continue
        }

        # Number input - toggle category
        $num = 0
        $isNumber = [int]::TryParse($rawInput, [ref]$num)

        if ($isNumber -and $num -ge 1 -and $num -le $total) {
            $catName = $categories[$num - 1]
            $selected[$catName] = -not $selected[$catName]
        } else {
            Write-Host "  Invalid input." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

# ==========================================
# Collect apps from selected categories
# ==========================================

function Get-AppsFromCategories {
    param($CategoryNames)

    $apps = @()

    foreach ($cat in $CategoryNames) {
        $catApps = $config.$cat
        if ($null -eq $catApps) {
            Write-Host "WARNING: Category '$cat' not found in apps.json - skipping." -ForegroundColor DarkYellow
            continue
        }
        $apps += @($catApps)
    }

    return @($apps)
}

# ==========================================
# App Status
# ==========================================
# ConvertFrom-WingetTable / Get-WingetStatusMaps are defined near the top of
# the script (needed by -Snapshot mode before this point is reached).

function Get-AppStatus {
    param($StatusMaps, [string]$AppId)

    $result = @{}

    if ($StatusMaps.Installed.ContainsKey($AppId)) {
        $result["Name"] = $StatusMaps.Installed[$AppId]
        if ($StatusMaps.Upgradable.ContainsKey($AppId)) {
            $result["Status"] = "update"
        } else {
            $result["Status"] = "installed"
        }
    } else {
        $result["Name"] = $AppId
        $result["Status"] = "new"
    }

    return $result
}

# ==========================================
# Preview
# ==========================================

function Show-Preview {
    param($Apps, $StatusMaps)

    Write-Host ""

    $countNew       = 0
    $countInstalled = 0
    $countUpdate    = 0

    foreach ($app in $Apps) {
        $status = Get-AppStatus $StatusMaps $app
        $label = "$($status.Name)  ($app)"

        if ($status.Status -eq "new") {
            Write-Host ("[NEW] {0}" -f $label) -ForegroundColor Green
            $countNew++
        } elseif ($status.Status -eq "update") {
            Write-Host ("[UPD] {0}" -f $label) -ForegroundColor Yellow
            $countUpdate++
        } else {
            Write-Host ("[OK]  {0}" -f $label) -ForegroundColor DarkGray
            $countInstalled++
        }
    }

    Write-Host ""
    $total = $Apps.Count
    $summaryLine = "Summary: $countNew to install  /  $countUpdate to update  /  $countInstalled already up to date  /  $total total"
    Write-Host $summaryLine -ForegroundColor Cyan
}

# ==========================================
# Install / Update Apps
# ==========================================

function Install-Apps {
    param($Apps, $StatusMaps)

    $results = @{ Installed = 0; Updated = 0; UpToDate = 0; Failed = 0 }

    foreach ($app in $Apps) {
        Write-Host ""

        $status = Get-AppStatus $StatusMaps $app

        if ($status.Status -ne "new") {
            Write-Host ("--- {0}  ({1})" -f $status.Name, $app) -ForegroundColor Cyan

            if ($status.Status -eq "update") {
                Write-Host "Updating..." -ForegroundColor Yellow
                winget upgrade --id $app -e --silent --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Updated successfully." -ForegroundColor Green
                    $results.Updated++
                } else {
                    Write-Host "Update failed (exit code $LASTEXITCODE)." -ForegroundColor Red
                    $results.Failed++
                }
            } else {
                Write-Host "Already up to date." -ForegroundColor DarkGray
                $results.UpToDate++
            }

        } else {
            Write-Host ("--- {0}" -f $app) -ForegroundColor Cyan
            Write-Host "Installing..." -ForegroundColor Green
            winget install --id $app -e --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("Installed: {0}" -f $app) -ForegroundColor Green
                $results.Installed++
            } else {
                Write-Host "Install failed (exit code $LASTEXITCODE)." -ForegroundColor Red
                $results.Failed++
            }
        }
    }

    return $results
}

# ==========================================
# MAIN
# ==========================================

# Winget sanity check
$wingetVersion = winget --version 2>$null
if (-not $wingetVersion) {
    Write-Host "ERROR: winget not found. Install App Installer from the Microsoft Store." -ForegroundColor Red
    exit 1
}

# Category selection
$selectedCategories = Show-CategoryMenu

Clear-Host
Write-Host ""
Write-Host "  Omega Winget Bootstrap (Optimized)" -ForegroundColor Cyan
Write-Host ("  winget {0}" -f $wingetVersion) -ForegroundColor DarkGray
Write-Host ""

$catLine = $selectedCategories -join ", "
Write-Host "  Categories : $catLine" -ForegroundColor Cyan

$apps = @(Get-AppsFromCategories $selectedCategories)
$apps = @(Remove-Duplicates $apps)

$appCount = $apps.Count
Write-Host "  Apps       : $appCount" -ForegroundColor DarkGray
Write-Host ""

# Batched status lookup - one `winget list` + one `winget upgrade` call
# total, instead of two winget calls per app.
$statusMaps = Get-WingetStatusMaps

# DryRun: show preview then exit
if ($DryRun) {
    Write-Host "Dry run mode - no changes will be made." -ForegroundColor Yellow
    Show-Preview $apps $statusMaps
    Write-Host ""
    Write-Host "Exiting (dry run)." -ForegroundColor Yellow
    exit 0
}

# Optional preview
$previewChoice = Read-Host "Check app status before proceeding? [y/N]"

if ($previewChoice -and $previewChoice.Trim().ToLower() -in @("y", "yes")) {
    Show-Preview $apps $statusMaps
    Write-Host ""
}

# Confirm
$confirm = Read-Host "Proceed with installation/update? [Y/n]"

if ($confirm -and $confirm.Trim().ToLower() -notin @("y", "yes", "")) {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Run
$summary = Install-Apps $apps $statusMaps

# Final summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "All done!" -ForegroundColor Green
Write-Host ("  Installed : {0}" -f $summary.Installed) -ForegroundColor Green
Write-Host ("  Updated   : {0}" -f $summary.Updated)   -ForegroundColor Yellow
Write-Host ("  Up to date: {0}" -f $summary.UpToDate)  -ForegroundColor DarkGray
if ($summary.Failed -gt 0) {
    Write-Host ("  Failed    : {0}" -f $summary.Failed) -ForegroundColor Red
}
Write-Host "======================================" -ForegroundColor Cyan
