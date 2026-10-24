[README.md](https://github.com/user-attachments/files/33900436/README.md)
# Steam Boot Switch — Big Picture Auto-Open & Auto-Close

**Controller connected during startup? Open Big Picture. Last controller disconnected when idle? Close Big Picture automatically.**

*Your Windows PC. Console when you want it, desktop when you don't.*

**Version:** `v1.0.0` · **Windows 10/11** · **Free, open-source (MIT license)** · **Unofficial—unaffiliated with Valve**

**First public release:** The core behaviors have been tested across repeated Windows restarts on the original living-room PC, including auto-open and guarded auto-close. The controller models tested so far are listed below. **Testing has been limited to one PC; Bluetooth controller support has not been tested.** This release is not a guarantee of compatibility with every controller or Windows configuration.

**Visual transitions:** Steam's small desktop window or a brief console may sometimes flash during startup or Big Picture exit, depending on Steam and Windows timing. v1.0.0 retains the faster transition checks from the final tested beta; a completely flicker-free transition cannot be guaranteed.

## Welcome!

**Auto-open for controller-first startup. Auto-close when your controllers disconnect (optional).** Steam stays running so you can switch back whenever you like.

Steam Boot Switch is a small Windows utility for living-room PCs that serve two roles: a Steam Machine-style gaming console and a regular keyboard-and-mouse computer. Steam can already start in Big Picture every time, but not everyone wants that. Steam Boot Switch checks for an active controller during your Windows sign-in and opens Big Picture *only when one is detected*. Connecting a controller later doesn't force a mode change; just use its Home/Steam button as usual.

The program also offers optional automatic Big Picture exit after the **last** controller disconnects, plus optional hiding of the regular Steam desktop window. It does **not** exit the Steam client itself.

### Before you install (important)

In **Steam → Settings → Interface**:

1. Turn **Run Steam when my computer starts** **ON**.
2. Turn **Start Steam in Big Picture Mode** **OFF**.

**Steam must launch on its own.** This utility watches for Steam and switches its interface; it doesn't replace Steam's startup process.

For reliable testing, leave a wired controller connected *before* restarting Windows. If using a wireless Steam Controller with a Puck/receiver, power the controller on early during boot so Steam can report it before the detection window closes. The receiver being plugged in alone does not mean a controller is on. The system checks during Windows **sign-in**, not before the lock screen; optional automatic Windows sign-in makes the experience more console-like, but reduces physical security and isn't configured by this utility.

## Install or upgrade

1. Download and **extract the entire ZIP** (do not run directly from inside the ZIP).
2. Double-click **`Install.vbs`**. A single settings window will appear.
3. Choose your preferences and click **Install / Upgrade**.
4. On the next Windows sign-in, leave a controller connected to test automatic Big Picture launch. After installation the watcher starts immediately in **monitor-only mode**; it won't open Big Picture just because you installed it mid-session.

**Already running a previous v8 beta?** Run the new **`Install.vbs` directly—no uninstall needed.** The installer keeps the existing internal Task Scheduler name and data directory for compatibility. It stages the new files and selected settings, compiles and checks the hidden launcher, then stops and replaces the previous watcher. It verifies the replacement watcher runs and, if upgrade validation fails, attempts to restore the previous version and scheduled task.

**Keep your previous working ZIP** until you've successfully tested an upgrade and a restart. Recovery is best-effort, not a substitute for a backup. Unlike prior beta instructions, you *should not need to uninstall first* for this version.

If Windows Script Host (`.vbs`) is blocked by workplace policy, fallback `.cmd` launchers are in `app/`. These display a console; don't override workplace security settings.

## Settings

The installer and `Settings.vbs` use one page. You can change settings later without reinstalling; changes take effect after the watcher restarts (for example, on your next sign-in).

| Preference | Default | Purpose |
| --- | --- | --- |
| Exit Big Picture on last-controller disconnect | **On** | Only automatic exit when no controller remains, no running game is detected, and status is sufficiently certain |
| Disconnect delay | **5 seconds** | Adjustable whole seconds, minimum 1; up to Windows' 32-bit maximum |
| Cancel exit when mouse/keyboard is used | **On** | Mouse movement or keyboard activity during the countdown permanently cancels that particular pending exit |
| After Big Picture: console-style hide Steam desktop | **On** | Steam stays running in the tray; turn off for traditional desktop-style Steam window handling. This may affect how Steam handles Guide/Home focus, but not the controller button itself |
| Pre-hide separate desktop window | **On** | Tries to avoid Steam's desktop window appearing while Big Picture is active |
| Desktop window sizing | **Preserve** | Alternatives: Maximize or a custom width and height |
| Cleanup delay | **0 milliseconds** | Additional delay before attempting to hide the Steam desktop window |
| Startup controller detection window | **120 seconds** | Allows slower Windows/Steam sign-in startup; does not continually launch Big Picture afterward |

**Game protection is always on:** a detected running game stops automatic exit. If you disconnect mid-game and the game closes later, Big Picture doesn't exit retroactively. A firmware update can look like a deliberate disconnect; the program cannot reliably distinguish the two. Turn off the auto-exit setting or use a longer delay when updating controller firmware, then restart the watcher to apply.

**Normal desktop mode remains normal:** turning off a controller while Steam's regular desktop UI is open will not hide or close that window.

## Controller compatibility

Steam Boot Switch reads Steam's *active connection events* for the wireless Steam Controller, rather than mistaking its always-plugged-in Puck for a powered-on controller. For other controllers, it combines Steam events with Windows' standard HID gamepad/joystick classifications. This avoids hardcoding controller names such as “DualSense Edge.”

### Tested on the original development PC

| Controller | Connection / test | Result |
| --- | --- | --- |
| Sony DualSense Edge | Wired USB-C, including reboot and disconnect tests | Worked |
| Steam Controller | Wireless via Valve Puck/receiver; on/off detection verified | Worked |
| Nintendo Switch 2 controller | Used successfully for a Windows restart / Big Picture auto-open test; connection method not recorded | Worked in that test |
| Bluetooth-paired controllers | **Not tested** | **Compatibility unknown** |

**Bluetooth support is not yet verified.** The tested wireless Steam Controller uses Valve's Puck, which should not be treated as evidence that ordinary Bluetooth controller connections work. Some adapters, virtual controllers, third-party drivers, and Bluetooth modes may not report an unambiguous active state. **Support is not universal or guaranteed.** Ambiguous status blocks automatic exit where possible.


## Choose a console-style or desktop-style Steam window

In the **Install / Upgrade** or **Settings** dialog, use **Console-style: hide Steam desktop window after Big Picture**:

- **On (default):** Steam's regular desktop window is hidden after Big Picture exits. Steam stays running in the tray. This favors a clean living-room experience.
- **Off:** The regular Steam window is left visible after Big Picture exits. This favors a traditional desktop experience.

This can also influence what happens when you press your controller's **Home / Guide / Steam** button, because Steam treats focused and unfocused windows differently. **Observed on the development PC:** After the first automatic Big Picture close, one subsequent Home/Guide press opened Big Picture directly; previously two presses were sometimes needed (first to focus Steam). This may vary by Steam version, focus state, controller and settings. It is an observation, **not a guaranteed or configurable button shortcut** in Steam Boot Switch. **The program does not intercept the button, and this option does not guarantee one-press versus two-press operation.** Use Steam's own controller settings if you need to change its Guide-button action.

## Optional: Start Steam quietly

If Steam's desktop window briefly appears before Big Picture, note that our watcher can only hide a window **after** Windows and Steam have created it. Valve supports the `-silent` Steam command-line option to start Steam in the system tray without opening its normal desktop UI. This can improve the transition on some setups. It is not required.

We **do not change Steam's startup registration**, and the installer does not modify Steam's registry keys. Many Steam installations already include `-silent` in their startup command. To inspect yours without changing anything, run this in PowerShell:

```powershell
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).Steam
```

If `-silent` is already there, nothing needs changing. If it isn't, consult [Valve's launch-options documentation](https://help.steampowered.com/en/faqs/view/0188-6BB7-D467-08E1) before making your own changes. Avoid duplicate Steam startup entries. **A brief window flash may come from another Windows startup app**, so don't assume Steam Boot Switch caused it without confirming.

## Built-in Steam Home button and current limitations

**Pressing the controller's Home/Guide/Steam button to open Big Picture is a Steam feature, not Steam Boot Switch.** Valve documents that you can use the controller's Home button to open Big Picture while using Steam. Depending on your Steam/controller settings, a single press may be sufficient. This program doesn't intercept that button or change Steam Input bindings. If you want to adjust the behavior, review **Steam > Settings > Controller**, including the setting commonly called *Guide Button Focuses Steam*. The exact options can vary with Steam updates and controller type.

**Steam desktop briefly visible during exit:** The separate Steam desktop window may appear for a fraction of a second when Big Picture closes. v1.0.0 uses adaptive, faster window checks to reduce that flash, but Steam owns the window creation and a completely invisible handoff is not guaranteed. **Preserve** is the recommended window-size setting for the most consistent desktop experience; choosing **Maximize** can itself briefly expose Steam while changing its window state.

**Rapid reconnects:** Controller presence is sampled approximately once per second in this release. If you cancel an automatic exit by moving the mouse, then reconnect and disconnect the controller very quickly, the watcher might miss the intervening reconnect. In that case it will safely leave Big Picture open instead of forcing an exit. Allow the controller to remain reconnected a couple of seconds before testing the next disconnect. This timing behavior is still being investigated.

**Brief PowerShell flash:** The installed launcher is intended to run hidden, and the author has verified a working hidden launcher and startup on the development machine, but a very brief terminal window was still reported on some boots. Its source has not been conclusively identified, and it may come from another startup task. We are not claiming a guaranteed zero-flash experience yet.

**Controller updates:** Firmware installations can temporarily disconnect the controller. The utility cannot reliably tell a firmware reset from a power-off. Before a firmware update, use `Settings.vbs` to turn off automatic exit and restart the watcher (e.g. sign out and back in) if you want to ensure the updater isn't interrupted by our exit logic.

**Automatic exit is conservative:** If a game is detected, any controller remains active, Windows input cancels the pending exit (when enabled), or controller state is uncertain, Big Picture stays open. Normal desktop Steam windows are not hidden merely because a controller disconnects.

**Compatibility:** Wired HID-class controllers are the primary intended use case; the Valve wireless Puck uses Steam's own connection events. The original PC also successfully used a Nintendo Switch 2 controller for a reboot test, but its connection method was not recorded. **Controllers connected through Bluetooth have not been tested.** Different drivers, adapters and virtual gamepads may behave differently.


## Logs, storage, and upgrades

Installed files live in `%LOCALAPPDATA%\SteamControllerBootMode` (the old internal name is kept to support in-place upgrades). Inside are the watcher script, settings code, a small locally compiled hidden launcher, `config.json`, and diagnostic logs. The Windows scheduled task retains the compatible name `SteamControllerBootMode_EarlyLogon_v8`.

**No cache is accumulated.** The application keeps only two rotating logs: `watcher.log` and `launcher.log`, with at most two backups each (`.1`, `.2`). Each file is capped around **512 KB**, so the runtime logs occupy roughly **3 MB** in total. The setup transcript is a **single overwritten file** named `SteamBootSwitch-setup.log` in your Windows temporary directory. Upgrades remove obsolete launcher binaries after the new watcher is verified, while preserving `config.json` and active logs.

The `app/` directory in the download contains the actual **source code**, not a cache. The three `.vbs` files in the download are simple windowless entry points for install, settings, and uninstall. Setup compiles `HiddenLauncher.cs` locally into a tiny `.exe` that quietly hosts the PowerShell watcher. **The entire program is not yet a single `.exe`.** That's a possible future packaging project, not a requirement for using it today.

## Uninstall

Double-click **`Uninstall.vbs`** from the extracted package (or use the fallback script). It unregisters the startup task, stops the watcher, and removes the installed folder. Steam itself and its settings are not changed. Keep the download ZIP if you'd like to reinstall.

## Troubleshooting

If automatic Big Picture entry fails after a restart, check:

```powershell
Get-ScheduledTask -TaskName 'SteamControllerBootMode_EarlyLogon_v8' | Select-Object TaskName,State
Get-Content "$env:LOCALAPPDATA\SteamControllerBootMode\launcher.log" -Tail 30
Get-Content "$env:LOCALAPPDATA\SteamControllerBootMode\watcher.log" -Tail 50
```

If upgrading fails, inspect the single installer log using:

```powershell
Get-Content "$env:TEMP\SteamBootSwitch-setup.log" -Tail 80
```

This first release has not yet been independently tested on another Windows PC. Please report startup failures, controller identity issues, or unexpected Big Picture exits with the relevant non-sensitive log excerpts.

## About this project

This is the author's **first project and first experience with vibe coding**, built through iterative AI-assisted development and hands-on testing on a personal Windows living-room gaming PC. At this stage it has **only been tested on that one system**, not broadly across other users' hardware. It is shared as an early community project for people with similar home-entertainment setups.

Optional cursor hiding is **not included**. If you use a mouse in your living-room setup, consider the separate [AutoHideMouseCursor utility from SoftwareOK](https://www.softwareok.com/?seite=Microsoft/AutoHideMouseCursor). It is not required or installed by this project.

Steam Boot Switch is an independent community project and is **not affiliated with Valve, Steam, Sony, Microsoft, or SoftwareOK**.

## Reporting a bug

When reporting a problem, include your Windows version, Steam client version, controller model/connection type, whether you restarted or shut down, the steps to reproduce, and the relevant lines from `watcher.log` or `launcher.log`. **Please redact user names, file paths, application titles, and other personal data from logs before posting publicly.** Logs are stored locally; this project does not upload them.

This release is distributed as inspectable scripts plus a small launcher compiled locally during installation. It is not code-signed. Only install it if you are comfortable running the supplied scripts, and retain your prior working ZIP during upgrades.
