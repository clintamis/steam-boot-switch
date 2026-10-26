# Steam Boot Switch V1.1.0

Intuitive Steam Big Picture: controller-aware startup, optional automatic exit,
Steam Controller Puck actions and a unified settings window.

## What's new since V1.0.0

- Native C# watcher with an isolated Puck worker, rebuilt from complete source.
- Cached process/state information and reduced stable-dock polling.
- Optional dock shutdown and three undock modes: disabled, on connection, or
  immediately after confirmed undocking.
- Steam game-process protection replaces fullscreen-application assumptions.
- Tested Preview 2 interface: compact gradient header, dark styling, lime switches
  and Startup and docking, Big Picture and Steam window sections.
- All 13 settings preserved, including validation, atomic saves, conflict handling
  and unknown values.
- Single graphical Windows installer, one Start Menu application, and Installed
  Apps uninstaller with settings preserve/export options.
- Recognized V1.0.0, native development and RC1 upgrades preserve settings.
- No-activate window hiding and deferred sizing; no experimental FocusGuard.

## Install or upgrade

Download **SteamBootSwitchSetup-1.1.0.exe**, verify its SHA-256 against
**SHA256SUMS.txt**, close Steam Boot Switch Settings, and run the installer.
Recognized installations can be upgraded in place. Settings opens after setup;
monitoring starts without forcing Big Picture open during installation.

In Steam Interface settings, enable **Run Steam when my computer starts** and
 disable **Start Steam in Big Picture Mode**. Open **Steam Boot Switch** from
 the Start Menu later to change preferences with **Save and apply**.
Uninstall through Windows Installed Apps; retain or export settings if wanted.
Steam, games, Steam startup settings and controller drivers are not modified.

## Assets

- `SteamBootSwitchSetup-1.1.0.exe` — Windows installer.
- `SteamBootSwitch-1.1.0-source.zip` — complete source, build instructions and tests.
- `SHA256SUMS.txt` — checksums for the release assets.
- `QA-REPORT.md` — verification results and test boundaries.

## Verification and known limitations

RC1 passed automated QA and owner-reported local Windows acceptance testing.
V1.1.0 was rebuilt with final metadata and rechecked; the attached QA report
records exact results. No additional cross-PC/controller matrix is claimed.
Idle resource measurements do not establish disconnect-time latency.

- Steam may occasionally take foreground focus when Big Picture closes.
- The installer is unsigned; Windows may show an unknown-publisher/SmartScreen warning.
- Cross-PC hardware compatibility testing is incomplete; Bluetooth is unverified.

Requires Windows 10/11, .NET Framework 4.8, Windows PowerShell 5.1 and Steam.
MIT licensed, copyright 2026 Steam Boot Switch contributors. Independent of
Valve and Microsoft. Built with AI assistance and tested on the author's PC.