# ==========================================
# Omega Winget Bootstrap
# Personal provisioning tool to bootstrap a fresh Windows environment
# using winget, category selection, and reproducible configs.
#
# Usage:
#   .\omega-winget-bootstrap.ps1 [-DryRun] [-Update]
#
# Recommended launch:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\omega-winget-bootstrap.ps1
# ==========================================

param(
    [switch]$DryRun,
    [switch]$Update
)

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
# Load Config
# ==========================================

$configPath = ".\apps.json"

if (!(Test-Path $configPath)) {
    Write-Host "ERROR: apps.json not found at $configPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# ==========================================
# Helpers
# ==========================================

function Remove-Duplicates {
    param($AppList)
    return $AppList | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique
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
        Write-Host "  Omega Winget Bootstrap" -ForegroundColor Cyan
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
        $apps += $catApps
    }

    return $apps
}

# ==========================================
# App Status Check (per-app, reliable)
# ==========================================

function Get-WingetName {
    param([string[]]$RawOutput, [string]$AppId)

    # Find the data line that contains the app ID and extract the name from it.
    # winget list output: "Name          Id            Version    Source"
    # The name is everything before the two-or-more spaces that precede the ID.
    foreach ($line in $RawOutput) {
        if ($line -match [regex]::Escape($AppId)) {
            $idIndex = $line.IndexOf($AppId)
            if ($idIndex -gt 0) {
                $name = $line.Substring(0, $idIndex).TrimEnd()
                # Trim trailing ellipsis winget adds when name is truncated
                $name = $name.TrimEnd('.')
                if ($name.Length -gt 0) {
                    return $name
                }
            }
        }
    }

    return $AppId
}

function Get-AppStatus {
    param([string]$AppId)

    $rawOutput = winget list --id $AppId -e --accept-source-agreements 2>$null
    $isInstalled = ($LASTEXITCODE -eq 0)

    if (-not $isInstalled) {
        $result = @{}
        $result["Status"] = "new"
        $result["Name"]   = $AppId
        return $result
    }

    $displayName = Get-WingetName $rawOutput $AppId

    winget upgrade --id $AppId -e --accept-source-agreements 2>$null | Out-Null
    $hasUpdate = ($LASTEXITCODE -eq 0)

    $result = @{}
    $result["Name"] = $displayName

    if ($hasUpdate) {
        $result["Status"] = "update"
    } else {
        $result["Status"] = "installed"
    }

    return $result
}

# ==========================================
# Preview
# ==========================================

function Show-Preview {
    param($Apps)

    Write-Host ""
    Write-Host "Checking app status (this may take a moment)..." -ForegroundColor DarkGray
    Write-Host ""

    $countNew       = 0
    $countInstalled = 0
    $countUpdate    = 0

    foreach ($app in $Apps) {
        $status = Get-AppStatus $app
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
    param($Apps)

    $results = @{ Installed = 0; Updated = 0; UpToDate = 0; Failed = 0 }

    foreach ($app in $Apps) {
        Write-Host ""

        $rawList = winget list --id $app -e --accept-source-agreements 2>$null
        $isInstalled = ($LASTEXITCODE -eq 0)

        if ($isInstalled) {
            $displayName = Get-WingetName $rawList $app
            Write-Host ("--- {0}  ({1})" -f $displayName, $app) -ForegroundColor Cyan

            winget upgrade --id $app -e --accept-source-agreements 2>$null | Out-Null
            $hasUpdate = ($LASTEXITCODE -eq 0)

            if ($hasUpdate) {
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
                # Fetch name now that it's installed
                $rawList = winget list --id $app -e --accept-source-agreements 2>$null
                $displayName = Get-WingetName $rawList $app
                Write-Host ("Installed: {0}" -f $displayName) -ForegroundColor Green
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
Write-Host "  Omega Winget Bootstrap" -ForegroundColor Cyan
Write-Host ("  winget {0}" -f $wingetVersion) -ForegroundColor DarkGray
Write-Host ""

$catLine = $selectedCategories -join ", "
Write-Host "  Categories : $catLine" -ForegroundColor Cyan

$apps = Get-AppsFromCategories $selectedCategories
$apps = Remove-Duplicates $apps

$appCount = $apps.Count
Write-Host "  Apps       : $appCount" -ForegroundColor DarkGray
Write-Host ""

# DryRun: show preview then exit
if ($DryRun) {
    Write-Host "Dry run mode - no changes will be made." -ForegroundColor Yellow
    Show-Preview $apps
    Write-Host ""
    Write-Host "Exiting (dry run)." -ForegroundColor Yellow
    exit 0
}

# Optional preview
$previewChoice = Read-Host "Check app status before proceeding? [y/N]"

if ($previewChoice -and $previewChoice.Trim().ToLower() -in @("y", "yes")) {
    Show-Preview $apps
    Write-Host ""
}

# Confirm
$confirm = Read-Host "Proceed with installation/update? [Y/n]"

if ($confirm -and $confirm.Trim().ToLower() -notin @("y", "yes", "")) {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Run
$summary = Install-Apps $apps

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