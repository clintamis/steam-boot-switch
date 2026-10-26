# Steam Boot Switch V1.1.1

**Intuitive Steam Big Picture.**

[Download V1.1.1](https://github.com/clintamis/steam-boot-switch/releases/tag/V1.1.1)
| [Changelog](CHANGELOG.md) | [Build from source](BUILDING.md) | [MIT license](LICENSE)

## WHAT IT DOES
Steam Boot Switch opens Steam Big Picture when you sign in to Windows with a
connected controller. It can also close Big Picture when the last controller
disconnects, without closing Steam.

The app is designed for living-room and home theater PCs that switch between
controller-based gaming and regular desktop use. Using Steam's built-in option
to start in Big Picture Mode means navigating out of Big Picture manually when
you want to use your PC normally. Steam Boot Switch reduces that friction by
checking for a controller at startup and making it easier to return to the
desktop when you finish using your controller.

You can customize how long Steam Boot Switch looks for a controller after
sign-in. You can also configure optional Steam Controller Puck actions, such as
turning off the controller when you dock it or opening Big Picture after you
undock it. The Puck must be connected to your PC for these features.

## GET STARTED - INSTALLATION INSTRUCTIONS
1. Download and double-click **SteamBootSwitchSetup-1.1.1.exe**.
2. Read the welcome screen and follow the graphical installer. Settings opens when installation finishes.
3. To change your preferences later, open "Steam Boot Switch" from the Windows
   Start Menu. Select "Save and apply" to save your changes.

In Steam Interface settings, enable **Run Steam when my computer starts** and
disable **Start Steam in Big Picture Mode**.

To open Big Picture automatically at sign-in, configure Steam to start when
you sign in to Windows. Steam Boot Switch does not configure Steam startup or
Windows automatic sign-in for you.

The installer starts controller monitoring without opening Big Picture during
installation. Test automatic startup behavior the next time you sign in to
Windows.

## MAIN SETTINGS

Startup and Docking
- Open Big Picture at Windows sign-in if a controller is connected. The default
  detection window is 120 seconds, adjustable from 15 to 600 seconds.
- Optionally turn off your Steam Controller when you place it on the Puck.
- Choose what happens when you lift the controller off the Puck: do nothing,
  open Big Picture when the controller connects, or open it immediately after
  a confirmed undock. Puck actions are optional, and automatic opening after
  undocking is disabled by default.

Big Picture
- Close Big Picture after the last controller disconnects while keeping Steam
  running. The default grace period for reconnecting is five seconds.
- Optionally cancel the pending exit when you use the keyboard or mouse.
- Check for active Steam game processes before exiting Big Picture.
  A fullscreen desktop application alone does not count as a game.
  Games launched outside Steam may not be recognized.

Steam Window
- Hide Steam's desktop window while Big Picture opens or after it closes.
- Set a delay before hiding the window, and choose whether to preserve its
  previous size, maximize it, or use custom dimensions.

## UPGRADING
Run the installer again over a compatible existing installation. Recognized
V1.0.0 installations are verified against archived source before their startup
task is migrated. The published V1.1.0 watcher is validated by executable
hash, stopped, and replaced with the named watcher. You do not need to
uninstall the previous version first. The installer preserves valid
saved settings and replaces recognized older UI versions and shortcuts with
one "Steam Boot Switch" Start Menu entry. It stops rather than overwriting
an unknown or different native watcher build or an incompatible settings
schema.

If you kept settings during uninstall, setup reuses them. Exported backups
can be restored by copying one to config.json while the app is stopped.
Setup does not silently import an old backup from Documents.

## UNINSTALLING
Open Windows Settings > Apps > Installed apps, find "Steam Boot Switch", and
select Uninstall.

Uninstall stops the background watcher and removes its known startup tasks,
application files, and shortcuts. You can choose to save a copy of your
settings to Documents first, or keep them in place for a later reinstall.
Application logs are removed. Steam, installed games, and controller drivers are
not uninstalled.

## WHERE FILES ARE STORED

Main application, settings, and logs:
  %LOCALAPPDATA%\SteamControllerBootMode
  (Typical path: C:\Users\<your-user>\AppData\Local\SteamControllerBootMode)

Settings file:
  %LOCALAPPDATA%\SteamControllerBootMode\config.json

Watcher log (if generated):
  %LOCALAPPDATA%\SteamControllerBootMode\watcher.log

Start Menu shortcut:
  %APPDATA%\Microsoft\Windows\Start Menu\Programs\Steam Boot Switch\Steam Boot Switch.lnk

Optional settings backup created during uninstall:
  %USERPROFILE%\Documents\SteamBootSwitch-settings-backup-YYYYMMDD-HHMMSSfff.json
  (Windows or OneDrive may redirect your Documents folder.)

Automatic startup:
  Per-user scheduled task: SteamControllerBootMode_EarlyLogon_v8
  If task registration is unavailable, setup uses a per-user Startup shortcut.

Steam Boot Switch's controller watcher runs in the background. The Settings
window runs only while it is open; you do not need to leave it open for
controller monitoring to work.

## SYSTEM REQUIREMENTS
- Windows 10 or Windows 11, Steam, and a compatible controller.
- .NET Framework 4.8 and built-in Windows PowerShell 5.1 for settings and
  setup maintenance. No PowerShell, CMD, or VBS windows appear during normal
  installation. Windows Script Host is not required to launch the installer.
  Setup checks .NET 4.8 and asks you to install it if it is missing.
- Development testing has included the Steam Controller with Puck, a wired
  DualSense Edge, and a wired Nintendo Switch 2 Pro Controller. Other
  controllers have not been tested and may not be detected in every setup.

## KNOWN LIMITATIONS
- On some PCs, Steam may take keyboard focus away from another app when Big
  Picture exits, interrupting typing or other application use.
- Controller detection depends partly on Steam and Windows behavior, which
  may vary by software version, connection type, and device.
- This installer is unsigned. Windows SmartScreen may show an unknown
  publisher warning. Verify the supplied SHA-256 before running it.
- The watcher and settings launcher are rebuilt from the included C# source.
  Experimental focus-recovery code is excluded.
- Automated clean-folder, upgrade, uninstall and migration checks passed on the
  development PC; the owner reports local RC1 Windows acceptance testing.
  Cross-PC compatibility testing remains incomplete.

## TROUBLESHOOTING
- If Big Picture does not open at sign-in, check that Steam starts with Windows,
  that a compatible controller was connected during the startup window, and
  that the setting is enabled.
- If an upgrade is refused, do not delete the current installation to force
  it. The installed native monitor may be newer or different from this release.
- If setup fails, its troubleshooting results are saved to:
    %TEMP%\SteamBootSwitch-Install-Result.txt
    %TEMP%\SteamBootSwitch-Preflight-Result.txt
    %TEMP%\SteamBootSwitch-Uninstall-Result.txt

Steam Boot Switch is an independent community utility and is not affiliated
with Valve or Microsoft. See CHANGELOG.txt for the V1.1 feature summary and
known issues.

## VALIDATION
V1.1.1 restores the installer welcome screen. Its final Windows build and QA
are pending. V1.1.0 passed automated build, settings, installer, migration and package checks. The owner reports RC1 local Windows acceptance
testing; no additional cross-PC acceptance testing is claimed. See
[QA-REPORT.md](QA-REPORT.md) for the checks performed and their limits. A fresh
install in an isolated folder on the development PC is not a clean-PC test.

## ABOUT AND SOURCE

This is the author's first vibe-coded project, developed with AI assistance and
hands-on testing on a personal Windows living-room PC. Bluetooth compatibility
remains unverified. The app does not intercept Home/Guide buttons or change Steam
Input bindings. Rapid reconnects and firmware updates can look like disconnects;
disable automatic exit while updating controller firmware.

Complete source and build instructions are in [BUILDING.md](BUILDING.md).
Component origins are in [SOURCE-PROVENANCE.md](SOURCE-PROVENANCE.md).
The engine is rebuilt from C#; no opaque recovered binary is needed.

Copyright (c) 2026 Steam Boot Switch contributors. [MIT licensed](LICENSE).
See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports and contributions.
Redact personal data from logs before posting them.
