$ErrorActionPreference='Stop'
$folder=Join-Path $env:LOCALAPPDATA 'SteamControllerBootMode'
$tasks=@('SteamControllerBootMode_EarlyLogon_v8','SteamControllerBootMode_EarlyLogon_v7','SteamControllerBootMode_EarlyLogon_v6')
$startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'Steam Controller Boot Mode.lnk'
Import-Module ScheduledTasks -ErrorAction Stop
foreach ($task in $tasks) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
        Write-Host "Removed task: $task"
    }
}
if (Test-Path $startup) {
    Remove-Item -LiteralPath $startup -Force
    Write-Host 'Removed fallback Startup shortcut.'
}
if (Test-Path $folder) {
    Set-Content -LiteralPath (Join-Path $folder 'stop.flag') -Value 'stop' -Encoding ASCII
    $watcher=Join-Path $folder 'SteamControllerBootMode.ps1'
    $running=$false
    for ($i=0;$i -lt 20;$i++) {
        $running=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($watcher) }).Count -gt 0
        if (!$running) { break }
        Start-Sleep -Seconds 1
    }
    # The v8-beta3 launcher remains alive with its child. Wait for both before deleting.
    # Versioned launchers (SteamBootHiddenLauncher-1.0.0.exe) must also exit.
    # A fixed executable name would miss the active process on uninstall.
    $activeLauncher=$false
    for ($i=0;$i -lt 20;$i++) {
        $activeLauncher=@(Get-CimInstance Win32_Process -Filter "Name LIKE 'SteamBootHiddenLauncher%'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (!$activeLauncher) { break }
        Start-Sleep -Seconds 1
    }
    if ($running -or $activeLauncher) {
        Write-Warning "Watcher still shutting down. After sign-out delete this folder: $folder"
    } else {
        try { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop }
        catch { Write-Warning "Could not remove $folder; delete manually after sign-out." }
    }
}
Write-Host 'Steam Boot Switch removed. Steam was not altered.' -ForegroundColor Green
Write-Host 'To return to v7, reinstall it from your previous v7 download.'
