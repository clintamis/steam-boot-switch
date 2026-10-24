# Steam Boot Switch v1.0.0 - transactional in-place install/upgrade.
# Retains the old internal folder/task names for backwards compatibility.
$ErrorActionPreference = 'Stop'
$folder = Join-Path $env:LOCALAPPDATA 'SteamControllerBootMode'
$taskName = 'SteamControllerBootMode_EarlyLogon_v8'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Steam Controller Boot Mode.lnk'
$watcher = Join-Path $folder 'SteamControllerBootMode.ps1'
$exeName = 'SteamBootHiddenLauncher-1.0.0.exe'
$exePath = Join-Path $folder $exeName
$version = '1.0.0'
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$stage = Join-Path $env:TEMP ('SteamBootSwitch-upgrade-' + [guid]::NewGuid().ToString('N'))
$back = Join-Path $stage 'previous'
$payload = @('SteamControllerBootMode.ps1', 'Settings.ps1', 'config.default.json', 'HiddenLauncher.cs')
$originalFiles = @{}
$hadTask = $false
$hadShortcut = $false
$hadInstallation = Test-Path -LiteralPath $folder
$previousLauncher = $null
$oldWatcherWasRunning = $false
$commitStarted = $false
$taskReplaced = $false
$installedBinaryStarted = $false
$installSucceeded = $false

function Get-InstalledWatcher {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($watcher) })
}
function Get-InstalledLaunchers {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue -Filter "Name LIKE 'SteamBootHiddenLauncher%'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) })
}
function Stop-RunningWatcher {
    if (!(Test-Path $folder)) { return }
    Set-Content -LiteralPath (Join-Path $folder 'stop.flag') -Value 'stop' -Encoding ASCII
    for ($i = 0; $i -lt 25; $i++) {
        if (@(Get-InstalledWatcher).Count -eq 0 -and @(Get-InstalledLaunchers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw 'The old watcher did not stop safely. No program files have been replaced.'
}
function Start-MonitorOnly([string]$binary) {
    if (!(Test-Path -LiteralPath $binary)) { throw "Missing launcher: $binary" }
    Remove-Item -LiteralPath (Join-Path $folder 'stop.flag') -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $binary -ArgumentList 'MonitorOnly' -WindowStyle Hidden | Out-Null
}
function Restore-PreviousInstall {
    Write-Warning 'Upgrade validation failed. Attempting to restore the previous installation.'
    try { Stop-RunningWatcher } catch { Write-Warning $_.Exception.Message }
    try {
        if ($hadTask) {
            $xml = Get-Content -LiteralPath (Join-Path $stage 'old-task.xml') -Raw
            Register-ScheduledTask -TaskName $taskName -Xml $xml -Force -ErrorAction Stop | Out-Null
        } else {
            $newTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($newTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
        }
    } catch { Write-Warning "Could not restore the prior Task Scheduler entry: $($_.Exception.Message)" }
    try {
        if ($hadShortcut) { Copy-Item -LiteralPath (Join-Path $stage 'old-shortcut.lnk') -Destination $startup -Force }
        elseif (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup -Force }
    } catch { Write-Warning "Could not restore old startup shortcut: $($_.Exception.Message)" }
    try {
        foreach ($name in @($payload + @('config.json', 'install-version.txt'))) {
            $dest = Join-Path $folder $name
            if ($originalFiles.ContainsKey($name) -and $originalFiles[$name]) {
                Copy-Item -LiteralPath (Join-Path $back $name) -Destination $dest -Force
            } elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
        }
        if (Test-Path -LiteralPath $exePath) {
            Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath (Join-Path $folder 'stop.flag') -Force -ErrorAction SilentlyContinue
        if ($oldWatcherWasRunning -and $previousLauncher -and (Test-Path $previousLauncher)) {
            Start-MonitorOnly $previousLauncher
        }
    } catch { Write-Warning "Could not fully restore old files: $($_.Exception.Message)" }
}

New-Item -ItemType Directory -Path $stage, $back -Force | Out-Null
try {
    foreach ($name in $payload) {
        if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))) { throw "Missing $name. Extract the entire download ZIP." }
    }
    Import-Module ScheduledTasks -ErrorAction Stop

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $hadTask = $null -ne $task
    if ($hadTask) {
        Export-ScheduledTask -TaskName $taskName | Set-Content -LiteralPath (Join-Path $stage 'old-task.xml') -Encoding Unicode
    }
    $hadShortcut = Test-Path -LiteralPath $startup
    if ($hadShortcut) { Copy-Item -LiteralPath $startup -Destination (Join-Path $stage 'old-shortcut.lnk') }
    if ($hadInstallation) {
        foreach ($name in @($payload + @('config.json', 'install-version.txt'))) {
            $target = Join-Path $folder $name
            $originalFiles[$name] = Test-Path -LiteralPath $target
            if ($originalFiles[$name]) { Copy-Item -LiteralPath $target -Destination (Join-Path $back $name) -Force }
        }
        $oldWatcherWasRunning = @(Get-InstalledWatcher).Count -gt 0
        $previousLauncher = Get-InstalledLaunchers | Select-Object -First 1 -ExpandProperty ExecutablePath
        if (!$previousLauncher) {
            $previousLauncher = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Actions.Execute } | Select-Object -First 1
        }
    }

    # Choose options BEFORE changing the current installation. Cancel keeps it intact.
    $configStage = Join-Path $stage 'config.json'
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Settings.ps1') -Installer -OutputPath $configStage
    if ($LASTEXITCODE -eq 2) { Write-Output 'Installation cancelled; existing installation unchanged.'; return }
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $configStage)) { throw 'Preferences dialog did not save successfully.' }
    # Validate json before changing anything, and compile the EXE outside the live app folder.
    $chosen = Get-Content -LiteralPath $configStage -Raw | ConvertFrom-Json -ErrorAction Stop
    if ([int]$chosen.disconnectGraceSeconds -lt 1) { throw 'Invalid disconnect delay.' }
    $stagedExe = Join-Path $stage $exeName
    Add-Type -Path (Join-Path $PSScriptRoot 'HiddenLauncher.cs') -OutputAssembly $stagedExe -OutputType WindowsApplication -ReferencedAssemblies 'System.dll','System.Windows.Forms.dll' -ErrorAction Stop
    if (!(Test-Path -LiteralPath $stagedExe) -or (Get-Item $stagedExe).Length -lt 4096) {
        throw 'Windows launcher compilation did not produce a usable file.'
    }
    Write-Output "Prepared and validated Steam Boot Switch $version."

    # COMMIT. No files are overwritten before this point.
    Stop-RunningWatcher
    $commitStarted = $true
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($name in $payload) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $folder $name) -Force }
    Copy-Item -LiteralPath $configStage -Destination (Join-Path $folder 'config.json') -Force
    Copy-Item -LiteralPath $stagedExe -Destination $exePath -Force

    $action = New-ScheduledTaskAction -Execute $exePath -WorkingDirectory $folder
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Steam Boot Switch ${version}: automatically open Big Picture at sign-in and optionally close it after disconnect" -Force -ErrorAction Stop | Out-Null
    $taskReplaced = $true

    # Start the new watcher now, WITHOUT entering Big Picture during installation.
    Start-MonitorOnly $exePath
    $installedBinaryStarted = $true
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        if (@(Get-InstalledWatcher).Count -gt 0) { break }
    }
    if (@(Get-InstalledWatcher).Count -eq 0) { throw 'The replacement background watcher did not start.' }
    Start-Sleep -Seconds 3
    if (@(Get-InstalledWatcher).Count -eq 0) { throw 'The replacement watcher exited immediately.' }
    $newAction = (Get-ScheduledTask -TaskName $taskName -ErrorAction Stop).Actions[0].Execute
    if ($newAction -ne $exePath) { throw 'The startup task is not pointing to the new launcher.' }

    Set-Content -LiteralPath (Join-Path $folder 'install-version.txt') -Value $version -Encoding Ascii
    # Once the replacement works, discard leftover launchers from past upgrades.
    foreach ($oldExe in @(Get-ChildItem -LiteralPath $folder -Filter 'SteamBootHiddenLauncher*.exe' -File -ErrorAction SilentlyContinue)) {
        if ($oldExe.FullName -ne $exePath) {
            Remove-Item -LiteralPath $oldExe.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue }
    foreach ($old in @('SteamControllerBootMode_EarlyLogon_v6','SteamControllerBootMode_EarlyLogon_v7')) {
        if (Get-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $old -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    # No cache is created. The app retains only rotating launcher/watcher logs.
    # Remove stale transient files from earlier versions, not any user settings.
    foreach ($obsolete in @('stop.flag','pause.flag')) {
        Remove-Item -LiteralPath (Join-Path $folder $obsolete) -Force -ErrorAction SilentlyContinue
    }
    $installSucceeded = $true
    Write-Output "Successfully installed/updated Steam Boot Switch $version."
    Write-Output 'Your settings were preserved or updated as selected.'
    Write-Output 'The background watcher is running in monitor-only mode.'
    Write-Output 'Automatic Big Picture boot check begins at your next Windows sign-in.'
} catch {
    $problem = $_.Exception.Message
    if ($commitStarted) { Restore-PreviousInstall }
    elseif (Test-Path $folder) {
        # No files/tasks changed: undo any signal sent to the existing watcher.
        Remove-Item -LiteralPath (Join-Path $folder 'stop.flag') -Force -ErrorAction SilentlyContinue
        if ($oldWatcherWasRunning -and @(Get-InstalledWatcher).Count -eq 0 -and $previousLauncher -and (Test-Path $previousLauncher)) {
            try { Start-MonitorOnly $previousLauncher } catch { }
        }
    }
    throw "Upgrade/install failed: $problem"
} finally {
    try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
