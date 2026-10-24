param(
    [switch]$DryRun,
    [switch]$Snapshot,
    [switch]$CleanupOnly,
    [switch]$MonitorOnly,
    [int]$StartupWindowSeconds = 30,
    [int]$DisconnectGraceSeconds = 5,
    [int]$PollSeconds = 1
)

# Steam Boot Switch v1.0.0 - Windows PowerShell 5.1; no modules or drivers.
# Steam is never force-terminated and no Steam preferences are edited.
$ErrorActionPreference = 'Stop'
$DataRoot = Join-Path $env:LOCALAPPDATA 'SteamControllerBootMode'
if (!(Test-Path $DataRoot)) { New-Item -Path $DataRoot -ItemType Directory -Force | Out-Null }
$LogPath = Join-Path $DataRoot 'watcher.log'
$StopPath = Join-Path $DataRoot 'stop.flag'
$StartTime = Get-Date
$LastMessage = ''
$script:LastSteamPath = $null
$script:SteamLogError = $false

# Maximum three log files total: active watcher.log plus watcher.log.1 and .2.
# Rotate in-process only; a single installed watcher owns this log.
function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    if ($DryRun -or $Snapshot -or $CleanupOnly) { Write-Host $line }
    try {
        if ((Test-Path -LiteralPath $LogPath) -and
            (Get-Item -LiteralPath $LogPath).Length -ge 524288) {
            $oldest = "$LogPath.2"; $middle = "$LogPath.1"
            Remove-Item -LiteralPath $oldest -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $middle) { Move-Item -LiteralPath $middle -Destination $oldest -Force }
            Move-Item -LiteralPath $LogPath -Destination $middle -Force
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { } # A log-write failure must never close Big Picture or crash the watcher.
}

$native = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace SteamBootWin {
  public static class API {
    public delegate bool EnumWindowProc(IntPtr hwnd, IntPtr param);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowProc callback, IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

  }
}
'@
try {
    if (-not ('SteamBootWin.API' -as [type])) { Add-Type -TypeDefinition $native }
    Add-Type -AssemblyName System.Windows.Forms
} catch {
    Write-Log "ERROR: Could not load Windows functions: $($_.Exception.Message)"
    exit 1
}

function Get-SteamFolder {
    if ($script:LastSteamPath -and (Test-Path (Join-Path $script:LastSteamPath 'steam.exe'))) { return $script:LastSteamPath }
    $folders = @()
    try { $folders += (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    try { $folders += (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    try { $folders += (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    try {
        $p = Get-CimInstance Win32_Process -Filter "Name='steam.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($p -and $p.ExecutablePath) { $folders += (Split-Path $p.ExecutablePath -Parent) }
    } catch { }
    if (${env:ProgramFiles(x86)}) { $folders += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    if ($env:ProgramFiles) { $folders += (Join-Path $env:ProgramFiles 'Steam') }
    foreach ($f in $folders) {
        if ($f -and (Test-Path (Join-Path $f 'steam.exe'))) {
            $script:LastSteamPath = $f
            return $f
        }
    }
    return $null
}

function Get-SteamRunning {
    return (@(Get-Process -Name steam -ErrorAction SilentlyContinue).Count -gt 0)
}

# VALIDATED BY THE USER 2026-10-23: controller_ui.txt slot 0 changed
# OFF -> ON -> OFF with the 2026 Steam Controller while the Puck stayed present.
# Do NOT count the Puck's USB interfaces or stale controller.txt signals.
# UI log indices are per-controller slots and may include other Steam controllers.
function Get-SteamLogControllers {
    $root = Get-SteamFolder
    if (!$root) { return [pscustomobject]@{ Known=$false; Count=0; Description='Steam folder not located' } }
    $path = Join-Path $root 'logs\controller_ui.txt'
    if (!(Test-Path $path)) {
        return [pscustomobject]@{ Known=$false; Count=0; Description='controller_ui.txt missing' }
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $boot = [datetime]$os.LastBootUpTime
        $lines = @(Get-Content -LiteralPath $path -Tail 5000 -ErrorAction Stop)
    } catch {
        return [pscustomobject]@{ Known=$false; Count=0; Description='Cannot read boot time or Steam UI log' }
    }
    $states = @{}
    $lastEvent = @{}
    $minTime = $boot.AddSeconds(-5)
    $events = 0
    foreach ($line in $lines) {
        if ($line -notmatch '^\[(?<dt>\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]') { continue }
        $timestamp = [datetime]::MinValue
        if (![datetime]::TryParseExact($Matches.dt, 'yyyy-MM-dd HH:mm:ss',
          [System.Globalization.CultureInfo]::InvariantCulture,
          [System.Globalization.DateTimeStyles]::None, [ref]$timestamp)) { continue }
        if ($timestamp -lt $minTime) { continue }
        if ($line -match '(?i)\bController\s+(\d+)\s+(connected|disconnected)\b') {
            $slot = $Matches[1]
            # Steam's log is append-ordered. Never mix controller.txt's separate states.
            $states[$slot] = ($Matches[2] -ieq 'connected')
            $lastEvent[$slot] = $timestamp
            $events++
        }
    }
    if ($events -eq 0) {
        return [pscustomobject]@{ Known=$false; Count=0;
            Description='No controller_ui events since this Windows boot; fail-safe unknown' }
    }
    $active = @($states.Keys | Where-Object { $states[$_] -eq $true })
    $desc = 'UI slots: ' + (@($states.Keys | Sort-Object {[int]$_} | ForEach-Object {
        $state = if ($states[$_]) { 'ON' } else { 'OFF' }
        "${_}=$state"
    }) -join ', ')
    return [pscustomobject]@{ Known=$true; Count=$active.Count; Description=$desc }
}

function Get-LastInputTick {
    $info = New-Object SteamBootWin.API+LASTINPUTINFO
    $info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
    if ([SteamBootWin.API]::GetLastInputInfo([ref]$info)) { return [long]$info.dwTime }
    return $null
}

# Device enumeration uses Windows PnP state, not controller vendor/friendly names.
# Avoid native WinMM/XInput polling: those APIs were present in earlier v8 betas
# that exited with STATUS_HEAP_CORRUPTION on the original DualSense Edge test PC.
# Match HID Generic Desktop gamepad (usage 0x05) or joystick (usage 0x04).
# This is best-effort detection, not a guarantee for every controller or dongle.
function Get-GenericControllers {
    try {
        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='HIDClass' AND Status='OK'" -ErrorAction Stop)
        $matches = @($devices | Where-Object {
            # Windows HIDClass puts usage classification in HardwareID. Its
            # CompatibleID collection may be empty (confirmed on a wired
            # DualSense Edge). Check both without relying on vendor names.
            $ids = @($_.HardwareID) + @($_.CompatibleID)
            $isGamepad = @($ids | Where-Object {
                $_ -match '(?i)^(?:HID_DEVICE_UP:0001_U:000[45]|HID_DEVICE_SYSTEM_GAME)$'
            }).Count -gt 0
            # Valve's wireless Puck can expose gamepad HID interfaces while
            # no controller is powered on. Trust Steam's UI connect events instead.
            $isValveReceiver = $_.DeviceID -match '(?i)^HID\\VID_28DE&'
            $isGamepad -and !$isValveReceiver
        })
        return [pscustomobject]@{
            Present=($matches.Count -gt 0); Known=$true
            Description="PnP_HID_Gamepads=$($matches.Count) (Valve receiver handled by Steam UI)"
        }
    } catch {
        return [pscustomobject]@{
            Present=$false; Known=$false
            Description="PnP controller enumeration unavailable: $($_.Exception.GetType().Name)"
        }
    }
}

function Get-Controllers {
    $s = Get-SteamLogControllers
    $g = Get-GenericControllers
    $present = ($g.Present -or ($s.Known -and $s.Count -gt 0))
    # A receiver must never be assumed active merely because its USB device exists.
    # Conservative automatic exit: require reliable generic polling and fresh Steam
    # UI history, except generic-only cases with no Steam UI events this boot.
    $known = $g.Known -and $s.Known
    # When Steam's controller log is unknown, only allow disconnect if we previously
    # observed a real generic controller; the main loop tracks that provenance.
    return [pscustomobject]@{
        Present=$present; FullyKnown=$known; SteamCount=$s.Count;
        SteamKnown=$s.Known; Generic=$g.Present; GenericKnown=$g.Known;
        Detail="$($s.Description); $($g.Description)"
    }
}

function Get-TopWindows {
    $results = New-Object 'System.Collections.Generic.List[object]'
    $callback = [SteamBootWin.API+EnumWindowProc] {
        param([IntPtr]$h, [IntPtr]$ignored)
        if (![SteamBootWin.API]::IsWindowVisible($h)) { return $true }
        $len = [SteamBootWin.API]::GetWindowTextLength($h)
        if ($len -lt 1) { return $true }
        $sb = New-Object System.Text.StringBuilder ($len + 2)
        [void][SteamBootWin.API]::GetWindowText($h, $sb, $sb.Capacity)
        $pidn = [uint32]0
        [void][SteamBootWin.API]::GetWindowThreadProcessId($h, [ref]$pidn)
        $pn = ''
        try { $pn = (Get-Process -Id $pidn -ErrorAction Stop).ProcessName } catch { }
        $r = New-Object SteamBootWin.API+RECT
        [void][SteamBootWin.API]::GetWindowRect($h, [ref]$r)
        $results.Add([pscustomobject]@{ Handle=$h; Title=$sb.ToString(); Process=$pn;
            Left=$r.Left; Top=$r.Top; Right=$r.Right; Bottom=$r.Bottom })
        return $true
    }
    [void][SteamBootWin.API]::EnumWindows($callback, [IntPtr]::Zero)
    return $results.ToArray()
}

function Test-FullDisplayRect($w) {
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $b = $screen.Bounds
        if (([math]::Abs($w.Left - $b.Left) -le 4) -and
            ([math]::Abs($w.Top - $b.Top) -le 4) -and
            ([math]::Abs($w.Right - $b.Right) -le 4) -and
            ([math]::Abs($w.Bottom - $b.Bottom) -le 4)) { return $true }
    }
    return $false
}
function Get-BigPictureWindows($windows) {
    # A fullscreen-sized desktop Steam window IS NOT Big Picture. In v3 this
    # kept BigPictureVisible=True after the user had exited BP, blocking cleanup.
    # User validated the exact title "Steam Big Picture Mode" on this machine.
    # If Valve changes the title, fail safely rather than hide an unknown window.
    return @($windows | Where-Object {
        ($_.Process -match '^(steam|steamwebhelper)$') -and
        ($_.Title -match '(?i)\bbig\s*picture\b')
    })
}

function Get-GameStatus($windows) {
    $root = Get-SteamFolder
    if (!$root) { return [pscustomobject]@{ Safe=$false; Reason='Steam folder unknown' } }
    $path = Join-Path $root 'logs\gameprocess_log.txt'
    if (!(Test-Path $path)) { return [pscustomobject]@{ Safe=$false; Reason='Game process log missing' } }
    try { $lines = @(Get-Content -LiteralPath $path -Tail 8000 -ErrorAction Stop) }
    catch { return [pscustomobject]@{ Safe=$false; Reason='Game process log unreadable' } }
    # Check Steam tracked game processes, and verify they're still alive.
    $tracked = @{}
    foreach ($line in $lines) {
        if ($line -match 'AppID\s+(\d+)\s+adding PID\s+(\d+)\s+as a tracked process') {
            $tracked[$Matches[2]] = $Matches[1]
        } elseif ($line -match 'AppID\s+\d+\s+no longer tracking PID\s+(\d+)') {
            $tracked.Remove($Matches[1])
        }
    }
    foreach ($pidString in @($tracked.Keys)) {
        if (Get-Process -Id ([int]$pidString) -ErrorAction SilentlyContinue) {
            return [pscustomobject]@{ Safe=$false; Reason="Steam game PID $pidString is running (AppID $($tracked[$pidString]))" }
        }
    }
    if (Get-Process -Name gameoverlayui -ErrorAction SilentlyContinue) {
        return [pscustomobject]@{ Safe=$false; Reason='Steam game overlay process active' }
    }
    # Conservative safety net for games launched outside Steam: fullscreen windows.
    foreach ($w in $windows) {
        if ($w.Process -match '^(steam|steamwebhelper|explorer|searchhost|applicationframehost|shellexperiencehost|textinputhost|startmenuexperiencehost|runtimebroker|lockapp|systemsettings|widgetservice|widgets|dwm|screenclippinghost|taskmgr|securityhealthsystray|chrome|msedge|firefox|brave|opera|vivaldi)$') { continue }
        if (Test-FullDisplayRect $w) {
            return [pscustomobject]@{ Safe=$false; Reason="Fullscreen app '$($w.Process)' detected" }
        }
    }
    return [pscustomobject]@{ Safe=$true; Reason='No Steam tracked game / fullscreen app found' }
}

# Only the main Steam Library/desktop window is hidden. Never hide Big Picture,
# chat, settings, or an unrelated app, and never hide Steam on a no-controller boot.
function Get-SteamDesktopWindows($windows) {
    return @($windows | Where-Object {
        $_.Process -match '^(steam|steamwebhelper)$' -and
        $_.Title -match '(?i)^Steam($|\s*[-|:])' -and
        $_.Title -notmatch '(?i)big\s*picture'
    } | Sort-Object @{ Expression = { if ($_.Title -eq 'Steam') { 0 } else { 1 } } })
}
function Hide-DesktopForTransition($windows, [string]$reason, [bool]$trackBoot) {
    if (!$script:CleanupEnabled -or !$script:PreHideDesktop -or $DryRun) { return }
    foreach ($w in @(Get-SteamDesktopWindows $windows)) {
        if ($trackBoot) { $script:bootHiddenWindows[[string]$w.Handle.ToInt64()] = $w.Handle }
        [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # SW_HIDE, leaves Steam running
        Write-Log "TRANSITION: Hid desktop Steam window before $reason."
    }
}
function Restore-BootHiddenWindows {
    # Only used if startup Big Picture FAILED to open. Never strand users with
    # a hidden Steam desktop just because Steam ignored the open URI.
    foreach ($h in @($script:bootHiddenWindows.Values)) {
        if ([SteamBootWin.API]::IsWindow($h)) {
            [void][SteamBootWin.API]::ShowWindow($h, 5) # SW_SHOW
        }
    }
    $script:bootHiddenWindows.Clear()
    Write-Log 'STARTUP FALLBACK: Restored desktop Steam windows because Big Picture did not open.'
}
function Start-BigPicture {
    Write-Log 'ACTION: Open Steam Big Picture.'
    if (!$DryRun) { Start-Process 'steam://open/bigpicture' }
}
# Cleanup must not depend solely on a Big Picture -> desktop title transition:
# Steam can take several seconds to re-create its desktop window.
function Request-SteamCleanup([string]$Reason) {
    if (!$script:CleanupEnabled) {
        Write-Log "CLEANUP SKIPPED (disabled): $Reason"
        return
    }
    $now = Get-Date
    $script:cleanupDue = $now.AddMilliseconds($script:CleanupDelayMs)
    $script:cleanupDeadline = $now.AddSeconds(18)
    Write-Log "Steam desktop cleanup queued ($Reason)."
}
function Stop-BigPicture($windows) {
    if (!$script:AutoExitEnabled) { Write-Log 'Automatic exit disabled by user.'; return }
    # Hide an existing desktop Steam window while Big Picture still covers it.
    Hide-DesktopForTransition $windows 'automatic Big Picture exit' $false
    Write-Log 'ACTION: Exit Big Picture using Steam URI (never exit Steam itself).'
    if (!$DryRun) { Start-Process 'steam://close/bigpicture' }
    Request-SteamCleanup 'automatic disconnect exit'
}

function Get-WindowBounds([IntPtr]$h) {
    $r = New-Object SteamBootWin.API+RECT
    if (-not [SteamBootWin.API]::GetWindowRect($h, [ref]$r)) { return $null }
    return [pscustomobject]@{ Left=$r.Left; Top=$r.Top; Right=$r.Right; Bottom=$r.Bottom;
        Width=($r.Right - $r.Left); Height=($r.Bottom - $r.Top) }
}
function Hide-SteamDesktop($windows) {
    # Hide ONLY the main desktop Steam window, not settings/friends/chat/BP.
    $candidates = @(Get-SteamDesktopWindows $windows)
    if ($candidates.Count -eq 0) {
        Write-Log 'Desktop Steam window not yet identified; will retry (or safely stop).'
        return $false
    }
    $w = $candidates[0]
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen
    $bounds = Get-WindowBounds $w.Handle
    if (!$bounds -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
        Write-Log 'CLEANUP SKIPPED: Cannot determine desktop Steam window size.'
        return $false
    }
    $winScreen = [System.Windows.Forms.Screen]::FromHandle($w.Handle)
    $isMaximized = [SteamBootWin.API]::IsZoomed($w.Handle)
    Write-Log "ACTION: Hide '$($w.Title)' FIRST (size=$($bounds.Width)x$($bounds.Height), maximized=$isMaximized); then adjust offscreen placement."
    if ($DryRun) { return $true }
    # Critical: do not visibly drag, restore or maximize Steam before hiding it.
    [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # SW_HIDE
    if ($winScreen.DeviceName -ne $primary.DeviceName) {
        # Only reposition when on a secondary monitor. Never apply a fixed
        # resolution. Preserve a maximized window's state as well.
        if ($isMaximized) {
            # SW_RESTORE can show an already-hidden window. Re-hide immediately.
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 9) # SW_RESTORE
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # SW_HIDE
            $bounds = Get-WindowBounds $w.Handle
            if (!$bounds) { Write-Log 'CLEANUP FAILED: no restored rectangle.'; return $false }
        }
        $area = $primary.WorkingArea
        # Position is clamped to a visible titlebar, never shrink user's size.
        $left = $area.Left + [int](($area.Width - $bounds.Width) / 2)
        $top = $area.Top + [int](($area.Height - $bounds.Height) / 2)
        $left = [math]::Max($area.Left, [math]::Min($left, $area.Right - 80))
        $top = [math]::Max($area.Top, [math]::Min($top, $area.Bottom - 80))
        # SWP_HIDEWINDOW|SWP_NOACTIVATE|SWP_NOZORDER keeps the move invisible.
        $moved = [SteamBootWin.API]::SetWindowPos($w.Handle, [IntPtr]::Zero, $left, $top, $bounds.Width, $bounds.Height, [uint32]0x0094)
        Write-Log "CLEANUP: Repositioned on primary while hidden; result=$moved, original size=$($bounds.Width)x$($bounds.Height)"
        if (!$moved) { return $false }
        if ($isMaximized) {
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 3) # restore maximize preference
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # ensure hidden again
        }
    } else {
        Write-Log 'CLEANUP: Steam window already on primary display; leaving size and maximized state unchanged.'
    }
    if ($script:WindowSizeMode -eq 'Maximize') {
        [void][SteamBootWin.API]::ShowWindow($w.Handle, 3) # SW_MAXIMIZE
        [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # ensure hidden again
        Write-Log 'CLEANUP: applied maximize preference, returned to hidden.'
    } elseif ($script:WindowSizeMode -eq 'Custom') {
        if ([SteamBootWin.API]::IsZoomed($w.Handle)) {
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 9) # SW_RESTORE
            [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # ensure hidden again
        }
        $cur = Get-WindowBounds $w.Handle
        if ($cur) {
            $primaryRect = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $cx = [math]::Max($primaryRect.Left, [int]($primaryRect.Left + ($primaryRect.Width - $script:WindowWidth)/2))
            $cy = [math]::Max($primaryRect.Top, [int]($primaryRect.Top + ($primaryRect.Height - $script:WindowHeight)/2))
            [void][SteamBootWin.API]::SetWindowPos($w.Handle, [IntPtr]::Zero, $cx, $cy, $script:WindowWidth, $script:WindowHeight, [uint32]0x0094)
            Write-Log "CLEANUP: applied custom restored size $($script:WindowWidth)x$($script:WindowHeight)."
        }
    }
    [void][SteamBootWin.API]::ShowWindow($w.Handle, 0) # last-chance re-hide; Steam keeps running.
    $stillVisible = [SteamBootWin.API]::IsWindowVisible($w.Handle)
    Write-Log "CLEANUP: originalWindowStillVisible=$stillVisible"
    return (!$stillVisible)
}

Write-Log "Started Steam Boot Switch v1.0.0. dryRun=$DryRun snapshot=$Snapshot cleanupOnly=$CleanupOnly monitorOnly=$MonitorOnly; startupWindow=${StartupWindowSeconds}s; disconnectGrace=${DisconnectGraceSeconds}s."
Write-Log "Steam folder: $(Get-SteamFolder)"
$configPath = Join-Path $DataRoot 'config.json'
try {
    $script:MouseActivityCancelsExit = $true
    $script:CleanupEnabled = $true
    $script:AutoExitEnabled = $true
    $script:PreHideDesktop = $true
    $script:CleanupDelayMs = 0
    $script:WindowSizeMode = 'Preserve'
    $script:WindowWidth = 1300
    $script:WindowHeight = 900
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $config.disconnectGraceSeconds) { $DisconnectGraceSeconds = [int]$config.disconnectGraceSeconds }
        if ($null -ne $config.startupWindowSeconds) { $StartupWindowSeconds = [int]$config.startupWindowSeconds }
        if ($null -ne $config.mouseActivityCancelsExit) {
            $script:MouseActivityCancelsExit = ($config.mouseActivityCancelsExit -eq $true)
        }
        if ($null -ne $config.autoExitOnDisconnect) { $script:AutoExitEnabled = ($config.autoExitOnDisconnect -eq $true) }
        if ($null -ne $config.cleanupSteamWindow) { $script:CleanupEnabled = ($config.cleanupSteamWindow -eq $true) }
        if ($null -ne $config.preHideSteamDesktop) { $script:PreHideDesktop = ($config.preHideSteamDesktop -eq $true) }
        if ($null -ne $config.cleanupDelayMs) { $script:CleanupDelayMs = [int]$config.cleanupDelayMs }
        if ($null -ne $config.windowSizeMode) { $script:WindowSizeMode = [string]$config.windowSizeMode }
        if ($null -ne $config.windowWidth) { $script:WindowWidth = [int]$config.windowWidth }
        if ($null -ne $config.windowHeight) { $script:WindowHeight = [int]$config.windowHeight }

    }
    if ($DisconnectGraceSeconds -lt 1 -or $DisconnectGraceSeconds -gt 2147483647) { throw 'disconnectGraceSeconds must be positive' }
    if ($StartupWindowSeconds -lt 15 -or $StartupWindowSeconds -gt 600) { throw 'startupWindowSeconds must be 15-600' }
    if ($script:CleanupDelayMs -lt 0 -or $script:CleanupDelayMs -gt 3000) { throw 'cleanupDelayMs must be 0-3000' }
    if ($script:WindowSizeMode -notin @('Preserve','Maximize','Custom')) { throw 'windowSizeMode must be Preserve, Maximize, or Custom' }
    if ($script:WindowWidth -lt 640 -or $script:WindowWidth -gt 7680 -or $script:WindowHeight -lt 480 -or $script:WindowHeight -gt 4320) { throw 'Invalid custom window dimensions' }

} catch {
    # Fail safe: disable automatic exit if the configuration is invalid.
    $script:AutoExitEnabled = $false
    $script:CleanupEnabled = $false
    Write-Log "Invalid configuration; disruptive actions disabled: $($_.Exception.Message)"
}
Write-Log "CONFIG: startup=${StartupWindowSeconds}s autoExit=$($script:AutoExitEnabled) grace=${DisconnectGraceSeconds}s cancelOnInput=$($script:MouseActivityCancelsExit) cleanup=$($script:CleanupEnabled) delayMs=$($script:CleanupDelayMs) sizeMode=$($script:WindowSizeMode)"

if ($Snapshot) {
    $c = Get-Controllers
    $ws = @(Get-TopWindows)
    $g = Get-GameStatus $ws
    Write-Log "CONTROLLERS: Generic=$($c.Generic), SteamUIActiveSlots=$($c.SteamCount), SteamKnown=$($c.SteamKnown), FullyKnown=$($c.FullyKnown), detail=$($c.Detail)"
    Write-Log "BIG PICTURE title matches: $(@(Get-BigPictureWindows $ws).Count)"
    Write-Log "GAMES: safeToExit=$($g.Safe), reason=$($g.Reason)"
    Write-Log 'STEAM WINDOWS (only visible window titles; no private data needed to troubleshoot):'
    foreach ($w in @($ws | Where-Object { $_.Process -match '^(steam|steamwebhelper)$' })) {
        Write-Log "  $($w.Process): '$($w.Title)' at [$($w.Left),$($w.Top)] to [$($w.Right),$($w.Bottom)]"
    }
    exit 0
}
if ($CleanupOnly) {
    # An explicit on-demand test, never launch/exit Big Picture or change startup.
    $ws = @(Get-TopWindows)
    if (@(Get-BigPictureWindows $ws).Count -gt 0) {
        Write-Log 'TEST CLEANUP SKIPPED: Big Picture is open; exit it manually first.'
        exit 2
    }
    $success = Hide-SteamDesktop $ws
    if (!$success) {
        Write-Log 'TEST CLEANUP INCOMPLETE: Desktop window could not be identified or hidden.'
        exit 3
    }
    Write-Log 'TEST CLEANUP COMPLETE: Steam desktop window hidden; Steam remains running.'
    exit 0
}

# Allow Windows + Steam to enumerate controller hardware; trigger automatic launch ONLY in this window.
$bootEnd = $StartTime.AddSeconds($StartupWindowSeconds)
$steamReadyDeadline = $bootEnd.AddSeconds(120)
$lastOpenAttempt = $null
$openAttempts = 0
$pendingStartLogged = $false
Write-Log "STARTUP: Controller detection allowed until $($bootEnd.ToString('HH:mm:ss')); Steam launch grace until $($steamReadyDeadline.ToString('HH:mm:ss'))."
$pendingOpen = $false
$didStartupDecision = $false
$prevPresent = $false
$prevFullyKnown = $false
$prevGeneric = $false
$genericOnlyEvidence = $false
$disconnectedAt = $null
$disconnectInputTick = $null
$knownBigPicture = $false
$cleanupDue = $null
$cleanupDeadline = $null
$lastStatus = ''
$lastControllerCheck = [datetime]::MinValue
$cachedControllers = $null
$script:bootHiddenWindows = @{}
$lastCimFrequencySeconds = 1

while ($true) {
    if (Test-Path $StopPath) { Write-Log 'Stop flag received; watcher exiting.'; break }
    $now = Get-Date
    try {
        if ($null -eq $cachedControllers -or ($now - $lastControllerCheck).TotalSeconds -ge $lastCimFrequencySeconds) {
            $cachedControllers = Get-Controllers
            $lastControllerCheck = Get-Date
        }
        $c = $cachedControllers
        $windows = @(Get-TopWindows)
        $bp = (@(Get-BigPictureWindows $windows).Count -gt 0)

        $status = "Generic=$($c.Generic) SteamCount=$($c.SteamCount) SteamKnown=$($c.SteamKnown) BigPictureVisible=$bp"
        if ($status -ne $lastStatus) { Write-Log "STATE: $status; $($c.Detail)"; $lastStatus=$status }

        if (!$MonitorOnly -and $now -le $bootEnd -and !$didStartupDecision -and $c.Present) {
            $pendingOpen = $true
            $didStartupDecision = $true
            Write-Log 'A controller was found during the initial startup window.'
        }
        if (!$MonitorOnly -and $pendingOpen) {
            if ($bp) {
                Write-Log 'STARTUP SUCCESS: Big Picture window detected.'
                $pendingOpen = $false
                $script:bootHiddenWindows.Clear()
            } elseif ($now -ge $steamReadyDeadline) {
                Write-Log 'STARTUP TIMEOUT: Steam Big Picture was not detected; stopping attempts until next sign-in.'
                $pendingOpen = $false
                if ($script:bootHiddenWindows.Count -gt 0) { Restore-BootHiddenWindows }
            } elseif ((Get-SteamRunning) -and ($null -eq $lastOpenAttempt -or ($now - $lastOpenAttempt).TotalSeconds -ge 12)) {
                if ($openAttempts -lt 6) {
                    $openAttempts++
                    $lastOpenAttempt = $now
                    Write-Log "STARTUP LAUNCH ATTEMPT $openAttempts/6: Steam process is running."
                    Hide-DesktopForTransition $windows 'opening Big Picture at startup' $true
                    Start-BigPicture
                } else {
                    Write-Log 'STARTUP RETRIES EXHAUSTED: Steam did not display Big Picture.'
                    $pendingOpen = $false
                    if ($script:bootHiddenWindows.Count -gt 0) { Restore-BootHiddenWindows }
                }
            }
        }

        if ($pendingOpen -and !$bp -and (Get-SteamRunning)) {
            Hide-DesktopForTransition $windows 'Big Picture startup transition' $true
        }

        if ($c.Present) {
            $disconnectedAt = $null
            $disconnectInputTick = $null
            $genericOnlyEvidence = $false
        } elseif ($script:AutoExitEnabled -and $prevPresent -and $bp -and
                (($prevFullyKnown -and $c.FullyKnown) -or
                 ($prevGeneric -and $c.GenericKnown -and !$c.Generic -and !$c.SteamKnown))) {
            # Generic-only fallback requires that we ACTUALLY observed a polled
            # controller, and Windows now reports that same generic input absent.
            # Never infer a disconnection from an idle Steam wireless receiver.
            $genericOnlyEvidence = ($prevGeneric -and $c.GenericKnown -and !$c.SteamKnown)
            $disconnectedAt = $now
            $disconnectInputTick = Get-LastInputTick
            Write-Log "Last controller disconnected in Big Picture. Waiting ${DisconnectGraceSeconds}s. Mouse/keyboard activity cancels exit=$($script:MouseActivityCancelsExit)."
        }
        if ($disconnectedAt) {
            $disconnectKnown = ($c.FullyKnown -or ($genericOnlyEvidence -and $c.GenericKnown -and !$c.SteamKnown))
            if (!$bp -or !$disconnectKnown -or $c.Present) {
                Write-Log 'Disconnect countdown cancelled: mode changed or controller status changed.'
                $disconnectedAt = $null
                $disconnectInputTick = $null
            } elseif ($script:MouseActivityCancelsExit) {
                $currentInputTick = Get-LastInputTick
                if ($null -eq $disconnectInputTick -or $null -eq $currentInputTick) {
                    # Fail safely if desktop interaction cannot be read.
                    Write-Log 'Disconnect countdown cancelled: input detection unavailable.'
                    $disconnectedAt = $null
                    $disconnectInputTick = $null
                } elseif ($currentInputTick -ne $disconnectInputTick) {
                    Write-Log 'Disconnect countdown cancelled permanently for this event: mouse/keyboard interaction detected.'
                    $disconnectedAt = $null
                    $disconnectInputTick = $null
                }
            }
        }
        if ($disconnectedAt -and ($now - $disconnectedAt).TotalSeconds -ge $DisconnectGraceSeconds) {
            # Single chance per actual disconnection. Neither further idle time nor
            # ending a game later can automatically request exit.
            $disconnectedAt = $null
            $disconnectInputTick = $null
            if (!$c.Present -and ($c.FullyKnown -or ($genericOnlyEvidence -and $c.GenericKnown -and !$c.SteamKnown)) -and $bp) {
                $g = Get-GameStatus $windows
                if ($g.Safe) { Stop-BigPicture $windows }
                else { Write-Log "Disconnect ignored: $($g.Reason). No deferred exit is scheduled." }
            } else { Write-Log 'Disconnect ignored: reconnected, uncertain state, or not in Big Picture.' }
        }
        if ($bp) {
            $knownBigPicture = $true
            # Optional illusion of a single surface: hide any separate Steam desktop
            # window behind Big Picture, BEFORE Big Picture closes. Does not quit Steam.
            Hide-DesktopForTransition $windows 'while Big Picture is visible' $false
        } elseif ($knownBigPicture) {
            $knownBigPicture = $false
            # Manual BP exits get the same desktop cleanup as automatic exits.
            if (!$cleanupDue) { Request-SteamCleanup 'manual Big Picture exit' }
        }
        if ($cleanupDue -and $now -ge $cleanupDue) {
            # Reuse this cycle's scan; transition scanning gets accelerated below.
            $latestWindows = $windows
            if (@(Get-BigPictureWindows $latestWindows).Count -gt 0) {
                # Steam has not actually left BP yet; don't touch its window.
                if ($now -ge $cleanupDeadline) {
                    Write-Log 'CLEANUP ABANDONED: Big Picture is still visible after timeout.'
                    $cleanupDue = $null
                } else {
                    $cleanupDue = $now.AddMilliseconds(125)
                }
            } else {
                $hidden = Hide-SteamDesktop $latestWindows
                if ($hidden) {
                    Write-Log 'CLEANUP COMPLETE: Steam desktop window is hidden; Steam remains running.'
                    $cleanupDue = $null
                } elseif ($now -ge $cleanupDeadline) {
                    Write-Log 'CLEANUP ABANDONED: Desktop Steam window was not identified or could not be hidden.'
                    $cleanupDue = $null
                } else {
                    $cleanupDue = $now.AddMilliseconds(125)
                }
            }
        }
        $prevPresent = $c.Present
        $prevFullyKnown = $c.FullyKnown
        $prevGeneric = $c.Generic
    } catch {
        # Failure safe: a failed read never authorizes closing Big Picture.
        Write-Log "WARN: skipped cycle: $($_.Exception.Message)"
        $cachedControllers = $null
        $disconnectedAt = $null
        $disconnectInputTick = $null
    }
    # Adaptive window scanning: while Big Picture is visible, hide a newly
    # exposed Steam desktop window quickly (including when the user exits BP
    # manually). Normal controller/CIM reads are still cached to ~1 second.
    # Never resize desktop Steam just to conceal it: that changes how the
    # window appears when someone deliberately reopens the desktop client.
    if ($pendingOpen -or ($null -ne $cleanupDue)) {
        Start-Sleep -Milliseconds 125
    } elseif ($bp -and $script:CleanupEnabled -and $script:PreHideDesktop) {
        Start-Sleep -Milliseconds 200
    } else {
        Start-Sleep -Seconds ([math]::Max(1, $PollSeconds))
    }
}
