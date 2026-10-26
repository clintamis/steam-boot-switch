$script:SbsDefaults = [ordered]@{
    autoOpenOnStartup=$true; startupWindowSeconds=120
    autoPowerOffOnDock=$false; undockBigPictureMode='Disabled'
    autoExitOnDisconnect=$true; disconnectGraceSeconds=5; mouseActivityCancelsExit=$true
    cleanupSteamWindow=$true; preHideSteamDesktop=$true; cleanupDelayMs=0
    windowSizeMode='Preserve'; windowWidth=1300; windowHeight=900
}
function Assert-SbsConfig($Config) {
    if ($null -eq $Config -or $Config -isnot [pscustomobject]) { throw 'Settings must be a JSON object.' }
    foreach ($key in $script:SbsDefaults.Keys) {
        if ($null -eq $Config.PSObject.Properties[$key]) {
            $Config | Add-Member -NotePropertyName $key -NotePropertyValue $script:SbsDefaults[$key]
        }
    }
    foreach ($key in @('autoOpenOnStartup','autoPowerOffOnDock','autoExitOnDisconnect','mouseActivityCancelsExit','cleanupSteamWindow','preHideSteamDesktop')) {
        if ($Config.$key -isnot [bool]) { throw "Invalid setting: $key must be true or false." }
    }
    $ranges=@{startupWindowSeconds=@(15,600);disconnectGraceSeconds=@(1,[int]::MaxValue);cleanupDelayMs=@(0,3000);windowWidth=@(640,7680);windowHeight=@(480,4320)}
    foreach ($key in $ranges.Keys) {
        $v=$Config.$key
        if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt $ranges[$key][0] -or $v -gt $ranges[$key][1]) { throw "Invalid value for $key." }
    }
    if ($Config.undockBigPictureMode -cnotin @('Disabled','Immediate','OnConnection')) { throw 'Invalid undock mode.' }
    if ($Config.windowSizeMode -cnotin @('Preserve','Maximize','Custom')) { throw 'Invalid window size mode.' }
}
function Read-SbsConfig([string]$Path, [switch]$AllowMissing) {
    if (![IO.File]::Exists($Path)) {
        if (!$AllowMissing) { throw 'Settings file not found. Install Steam Boot Switch first.' }
        $c=[pscustomobject]@{}
    } else {
        $c=[IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
    }
    Assert-SbsConfig $c
    return $c
}
function Save-SbsConfig([string]$Path, $Baseline, $Chosen, [switch]$AllowCreate) {
    Assert-SbsConfig $Chosen
    $exists=[IO.File]::Exists($Path)
    $before=if($exists){[IO.File]::ReadAllText($Path)}else{$null}
    $latest=Read-SbsConfig $Path -AllowMissing:$AllowCreate
    $changed=@()
    foreach ($key in $script:SbsDefaults.Keys) {
        if (!$exists -or $Chosen.$key -cne $Baseline.$key) {
            if ($exists -and $latest.$key -cne $Baseline.$key -and $latest.$key -cne $Chosen.$key) {
                throw 'This setting was changed in another window. Close and reopen Settings before saving.'
            }
            if (!$exists -or $latest.$key -cne $Chosen.$key) { $latest.$key=$Chosen.$key; $changed+=,$key }
        }
    }
    if ($changed.Count -eq 0) { return [pscustomobject]@{ Changed=@(); RestartRequired=$false } }
    Assert-SbsConfig $latest
    $directory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    [void][IO.Directory]::CreateDirectory($directory)
    $temp=[IO.Path]::Combine($directory,('config.'+[guid]::NewGuid().ToString('N')+'.tmp'))
    try {
        $json=$latest | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
        # Recheck after serialization so an externally edited file is not silently replaced.
        if ($exists) {
            if ([IO.File]::ReadAllText($Path) -cne $before) { throw 'Settings changed while saving. Reopen this window and try again.' }
            $backup=$Path+'.before-unified-settings'
            if (![IO.File]::Exists($backup)) { [IO.File]::Copy($Path,$backup,$false) }
            [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)
        } else { [IO.File]::Move($temp,$Path) }
    } finally { if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)} }
    return [pscustomobject]@{Changed=$changed;RestartRequired=(@($changed | Where-Object {$_ -ne 'undockBigPictureMode'}).Count -gt 0)}
}
function Restart-SbsMonitor([string]$Root) {
    $exe=Join-Path $Root 'SteamBootSwitch.exe'
    $flag=Join-Path $Root 'stop.flag'
    if (![IO.File]::Exists($exe)) { throw 'Monitor executable not found. Settings are saved for the next start.' }
    function Get-SettingsMonitorInstances {
        @(Get-CimInstance Win32_Process -Filter "Name='SteamBootSwitch.exe'" -ErrorAction Stop | Where-Object {$_.ExecutablePath -ieq $exe})
    }
    if (@(Get-SettingsMonitorInstances).Count -eq 0) { return 'Settings saved. They will apply when the monitor next starts.' }
    if ([IO.File]::Exists($flag)) { throw 'Another operation is stopping the monitor. Settings are saved; apply them after that operation finishes.' }
    try {
        [IO.File]::WriteAllText($flag,'stop')
        for($i=0;$i -lt 60;$i++) {
            if (@(Get-SettingsMonitorInstances).Count -eq 0) { break }
            Start-Sleep -Milliseconds 400
        }
        if (@(Get-SettingsMonitorInstances).Count -gt 0) { throw 'The monitor did not stop. Settings are saved for its next restart.' }
    } finally { if ([IO.File]::Exists($flag)) { [IO.File]::Delete($flag) } }
    Start-Process -FilePath $exe -ArgumentList '--monitor-only' -WindowStyle Hidden | Out-Null
    for($i=0;$i -lt 35;$i++) {
        if (@(Get-SettingsMonitorInstances).Count -ge 1) { return 'Settings applied. Sign-in options take effect at your next sign-in. Re-dock before testing.' }
        Start-Sleep -Milliseconds 400
    }
    throw 'Settings are saved, but the native monitor did not restart. Check watcher.log.'
}
