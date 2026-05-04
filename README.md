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