# Steam Boot Switch V1.1.1 - Welcome screen and watcher identity

V1.1.1 restores the explanatory welcome screen in the Windows installer and gives its background watcher a recognizable name and icon.

## Changes since V1.1.0
- The installer now explains Steam Boot Switch's controller-aware Big Picture behavior before installation.
- The welcome page shows the actual installation folder and Start Menu shortcut.
- Existing configurations trigger an upgrade-only message explaining that saved settings are preserved.
- Task Manager identifies the watcher as Steam Boot Switch and shows the embedded application icon.
- Upgrades recognize the V1.1.0 watcher, preserve settings, replace its startup action, and remove the old executable after the new watcher starts.
- Controller, Puck, Steam game protection, and settings behavior remain unchanged.

## Installation
Download `SteamBootSwitchSetup-1.1.1.exe` and verify its SHA-256 against
`SHA256SUMS.txt`. Close Steam Boot Switch Settings before running the installer.
Compatible existing installations can upgrade in place; do not uninstall first.

## Known limitations
The installer remains unsigned. Steam can occasionally take foreground focus
when Big Picture closes. Cross-PC and Bluetooth testing remains incomplete.

**Release status:** prepared as a draft for review. It has not been published.
