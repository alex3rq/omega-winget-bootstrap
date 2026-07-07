# 🪟 Omega Winget Bootstrap

Personal provisioning tool to bootstrap a fresh Windows environment using **winget**, interactive category selection, and reproducible configs.

---

## Features

- Interactive multi-select menu — toggle individual categories or load a preset
- Categories driven by `apps.json` — add a new key, it shows up automatically in the menu
- Reliable per-app status detection via `$LASTEXITCODE` — no brittle output parsing
- Optional pre-flight preview showing `[NEW]` / `[UPD]` / `[OK]` per app
- Dry run mode to inspect changes before committing
- Final summary: installed / updated / up-to-date / failed
- `-Update` flag to upgrade all installed apps at once
- Compatible with Windows PowerShell 5.1 and PowerShell 7+

---

## Requirements

- Windows 10 1809+ or Windows 11
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (ships with **App Installer** from the Microsoft Store)

---

## Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/alex3rq/omega-winget-bootstrap
cd omega-winget-bootstrap

# 2. Edit apps.json with your app list

# 3. Run
powershell -NoProfile -ExecutionPolicy Bypass -File .\omega-winget-bootstrap.ps1
```

---

## Usage

```
.\omega-winget-bootstrap.ps1 [options]
```

| Flag       | Description                                                    |
|------------|----------------------------------------------------------------|
| `-DryRun`  | Show what would be installed/updated — no changes made         |
| `-Update`  | Upgrade all installed apps (`winget upgrade --all`) then exit  |

### Examples

```powershell
# Interactive category picker
.\omega-winget-bootstrap.ps1

# Preview what the selected categories would do — no changes
.\omega-winget-bootstrap.ps1 -DryRun

# Update all installed apps
.\omega-winget-bootstrap.ps1 -Update
```

---

## Optimized Variant + Snapshot Mode

`omega-winget-bootstrap.optimized.ps1` is a faster variant of the script: it batches winget status checks into one `winget list` + one `winget upgrade` call instead of two calls per app, and adds a `-Snapshot` mode.

```
.\omega-winget-bootstrap.optimized.ps1 [-DryRun] [-Update] [-Snapshot] [-SnapshotPath <path>] [-ConfigFile <path>]
```

| Flag              | Description                                                                          |
|-------------------|---------------------------------------------------------------------------------------|
| `-Snapshot`       | Scan currently-installed apps (`winget export`) and write a category-keyed json file (default `apps-omega.json`) |
| `-SnapshotPath`   | Override the snapshot output path (default `apps-omega.json`)                        |
| `-ConfigFile`     | Load a specific config file instead of the auto-detected default                     |

Apps that are already listed in `apps.json` keep their category in the snapshot; anything installed but not curated there is grouped under `"Uncategorized"` so nothing gets silently dropped. Only apps from the winget catalog source are included (Microsoft Store apps aren't reinstallable via `winget install --id`, so they're skipped).

Once `apps-omega.json` exists, normal runs (`-DryRun` or otherwise) auto-load it instead of `apps.json` — no flag needed. Pass `-ConfigFile apps.json` to opt back into the general list even if a snapshot exists.

```powershell
# Capture your current machine setup
.\omega-winget-bootstrap.optimized.ps1 -Snapshot

# Later runs (or on a fresh machine, after copying apps-omega.json) auto-use the snapshot
.\omega-winget-bootstrap.optimized.ps1

# Force the general apps.json even though a snapshot exists
.\omega-winget-bootstrap.optimized.ps1 -ConfigFile apps.json
```

Re-run `-Snapshot` any time to refresh `apps-omega.json` against your current setup — it's a full rescan, not a merge.

`apps-omega.json` is a personal machine snapshot, not a curated list — add it to `.gitignore` if you don't want to commit it, or keep it versioned if you want a portable copy of your own setup.

---

## Interactive Menu

When the script launches, you get a toggle menu:

```
  Omega Winget Bootstrap
  Select categories to install:

   1)  [ ]  RuntimesAndDrivers
   2)  [ ]  CoreSystem
   3)  [ ]  Networking
   4)  [ ]  Downloads
   5)  [ ]  Peripherals
   6)  [ ]  Development
   7)  [ ]  Communication
   8)  [ ]  Media
   9)  [ ]  Gaming
  10)  [ ]  Streaming
  11)  [ ]  Design

  ----------------------------------------
   P)  Load preset
   A)  Select all
   C)  Clear all
   Q)  Confirm and continue

  Selected: (none)

  Enter number, or command:
```

Type a number to toggle a category on/off. Type `P` to load a preset, `A` to select all, `C` to clear, `Q` to confirm and proceed.

### Built-in Presets

| # | Name        | Categories                                                    |
|---|-------------|---------------------------------------------------------------|
| 1 | Core Setup  | RuntimesAndDrivers, CoreSystem                                |
| 2 | Dev         | RuntimesAndDrivers, CoreSystem, Development, Networking       |
| 3 | Gaming      | RuntimesAndDrivers, CoreSystem, Gaming, Downloads, Peripherals|
| 4 | Streaming   | RuntimesAndDrivers, CoreSystem, Streaming, Media              |
| 5 | Full        | All categories                                                |

---

## apps.json

Organized by category. Use winget package IDs — find them with `winget search <name>`.

| Category            | Contents                                                      |
|---------------------|---------------------------------------------------------------|
| `RuntimesAndDrivers`| VCRedist, .NET, DirectX, GameInput, HidHide, ViGEmBus         |
| `CoreSystem`        | Shell, utilities, password manager, file tools, system tweaks |
| `Networking`        | VPN, remote access, LAN sharing                               |
| `Downloads`         | Torrent client, download managers                             |
| `Peripherals`       | Controller software, capture cards, RGB, RTSS                 |
| `Development`       | Git, Node, Python, Docker, editors, IDEs, AI tools            |
| `Communication`     | Browsers, messaging, notes                                    |
| `Media`             | Video, audio, codecs, screen capture, upscaling               |
| `Gaming`            | Launchers, overlays, library managers                         |
| `Streaming`         | OBS, stream deck, capture utilities                           |
| `Design`            | Vector, raster, 3D                                            |

Adding a new category is as simple as adding a new key to `apps.json` — no script changes needed.

---

## Preview Mode

When prompted `Check app status before proceeding? [y/N]`, the script queries winget for each app and shows:

| Tag     | Meaning                        |
|---------|--------------------------------|
| `[NEW]` | Not installed — will install   |
| `[UPD]` | Installed, update available    |
| `[OK]`  | Installed and up to date       |

This is optional because it runs one winget query per app. `-DryRun` always triggers it automatically.

---

## License

MIT