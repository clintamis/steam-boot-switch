# Steam Boot Switch v1.0.0

**Big Picture Auto-Open & Auto-Close**  
*Your Windows PC. Console when you want it, desktop when you don't.*

Steam Boot Switch lets a Windows living-room gaming PC open Steam Big Picture automatically **only when a controller is connected during Windows sign-in**. Boot without a controller to keep the normal desktop. If enabled, Big Picture can also close automatically after the **last controller disconnects**, once the configurable delay has passed and no game is running. Mouse/keyboard activity can cancel an exit. Steam itself stays running.

### Before installing

In **Steam → Settings → Interface**, turn **Run Steam when my computer starts** ON and **Start Steam in Big Picture Mode** OFF. Extract the ZIP; use `Install.vbs` to install or upgrade, `Settings.vbs` to adjust preferences, or `Uninstall.vbs` to remove it.

### Default behavior

- Automatic Big Picture launch only during the Windows startup/sign-in detection window
- Automatic Big Picture exit enabled, with **5-second** disconnect grace period (minimum configurable value: 1 second)
- Don't auto-exit when a game is running, another controller remains connected, or state is uncertain
- Cancel a pending disconnect-triggered exit if mouse/keyboard activity is detected
- Optionally hide the Steam desktop window after Big Picture exits, without quitting Steam

### Tested hardware and limitations

Tested **only on one Windows PC**. Successful tests included a **wired USB-C DualSense Edge**, a **Steam Controller through its Valve Puck**, and a **Nintendo Switch 2 controller** used for a restart test (connection method not recorded). **Bluetooth-paired controllers have not been tested; Bluetooth compatibility is unknown.** These successes do not establish universal compatibility.

There may still be a momentary Steam-window or console flash, unusually fast disconnect/reconnect events can be missed, and firmware updates may look like intentional disconnections. See the README for safety notes and troubleshooting.

### Acknowledgement

This is the author's **first vibe-coded software project**, made with AI assistance and tested on the personal Windows home-entertainment PC it was created for. It is not affiliated with Valve or Steam. Source code is included under the MIT license. The launcher is compiled locally during installation and is **not code-signed**.
