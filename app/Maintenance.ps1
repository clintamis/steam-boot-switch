param([ValidateSet('Preflight','Install','Uninstall')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Root, [switch]$TestMode,
    [ValidateSet('Keep','Export','Delete')][string]$SettingsAction='Keep')
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$exe=Join-Path $Root 'SteamBootSwitchNative-alpha4.exe'
$taskName=if($TestMode){'SteamBootSwitch_V110_QA'}else{'SteamControllerBootMode_EarlyLogon_v8'}
$group=if($TestMode){'Steam Boot Switch V1.1.0 QA'}else{'Steam Boot Switch'}
$programs=Join-Path ([Environment]::GetFolderPath('Programs')) $group
$startup=Join-Path ([Environment]::GetFolderPath('Startup')) ($group+' Monitor.lnk')
$result=Join-Path $env:TEMP ('SteamBootSwitch-'+$Mode+'-Result.txt')
. (Join-Path $PSScriptRoot 'LegacyUpgrade.ps1')
$legacyRecognized=Test-SbsV1 $Root
$legacyExe=Join-Path $Root 'SteamBootHiddenLauncher-1.0.0.exe'
function Instances {
    @(Get-CimInstance Win32_Process -Filter "Name='SteamBootSwitchNative-alpha4.exe'" |
        Where-Object {$_.ExecutablePath -ieq $exe})
    if($legacyRecognized){Get-SbsV1Processes $Root}
}
function Check-Path {
    $p=$Root
    while($p){
        if([IO.Directory]::Exists($p) -and (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'Installation path contains a junction or symbolic link.'}
        $p=[IO.Path]::GetDirectoryName($p)
    }
    foreach($f in @('config.json','SteamBootSwitchNative-alpha4.exe','stop.flag','SteamControllerBootMode.ps1','HiddenLauncher.cs','SteamBootHiddenLauncher-1.0.0.exe','rc1-backup')){
        $p=Join-Path $Root $f
        if([IO.File]::Exists($p) -and (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw "Unsafe linked file: $f"}
    }
}
function Stop-Owned {
    if(@(Instances).Count -eq 0){return}
    [IO.File]::WriteAllText((Join-Path $Root 'stop.flag'),'stop')
    for($i=0;$i -lt 60;$i++){
        if(@(Instances).Count -eq 0){break}; Start-Sleep -Milliseconds 400
    }
    foreach($p in @(Instances)){Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop}
    if(@(Instances).Count -ne 0){throw 'Steam Boot Switch could not be stopped.'}
}
function Owned-Tasks {
    @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
        $actions=@($_.Actions)
        $_.TaskName -like 'Steam*' -and $actions.Count -eq 1 -and
        ((([string]$actions[0].Execute).Trim('"') -ieq $exe) -or
          ($legacyRecognized -and ([string]$actions[0].Execute).Trim('"') -ieq $legacyExe))
    })
}
function Check-Task {
    $t=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if($t -and (@($t.Actions).Count -ne 1 -or
      (([string]$t.Actions[0].Execute).Trim('"') -ine $exe -and
       !($legacyRecognized -and ([string]$t.Actions[0].Execute).Trim('"') -ieq $legacyExe)))){
        throw 'A startup task with this name belongs to a different installation.'
    }
}
try {
    Check-Path
    . (Join-Path $PSScriptRoot 'Settings.Core.ps1')
    $cfg=Join-Path $Root 'config.json'
    if($Mode -eq 'Uninstall'){
        $settingsScript=Join-Path $Root 'Settings.ps1'
        foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")){
            if($p.CommandLine -and $p.CommandLine.IndexOf($settingsScript,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw 'Close Steam Boot Switch Settings before uninstalling.'}
        }
    }
    if($Mode -eq 'Preflight'){
        if([IO.File]::Exists($cfg)){[void](Read-SbsConfig $cfg)}
        if([IO.File]::Exists($Root+'\SteamControllerBootMode.ps1') -and !$legacyRecognized){throw 'Unrecognized legacy watcher source. No files were replaced.'}
        if([IO.File]::Exists($exe)){
            $known=[IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'recognized-engines.txt'))
            if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -notin $known){throw 'Unknown watcher version. Setup will not overwrite it.'}
        }
        Check-Task
        # Refuse to replace an open settings UI: it may contain unsaved choices.
        $settingsScript=Join-Path $Root 'Settings.ps1'
        foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")){
            if($p.CommandLine -and $p.CommandLine.IndexOf($settingsScript,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw 'Close Steam Boot Switch Settings before upgrading.'}
        }
        if([IO.File]::Exists($exe)){
            [void][IO.Directory]::CreateDirectory((Join-Path $Root 'rc1-backup'))
            [IO.File]::Copy($exe,(Join-Path $Root 'rc1-backup\SteamBootSwitchNative-alpha4.exe'),$true)
            if([IO.File]::Exists($cfg)){[IO.File]::Copy($cfg,(Join-Path $Root 'rc1-backup\config.json'),$true)}
        }
        if($legacyRecognized){
            [void][IO.Directory]::CreateDirectory((Join-Path $Root 'rc1-backup'))
            foreach($name in @('SteamControllerBootMode.ps1','HiddenLauncher.cs','SteamBootHiddenLauncher-1.0.0.exe','config.json')){
                $old=Join-Path $Root $name
                if([IO.File]::Exists($old)){[IO.File]::Copy($old,(Join-Path $Root ('rc1-backup\'+$name)),$true)}
            }
        }
        Stop-Owned
    } elseif($Mode -eq 'Install'){
        if(![IO.File]::Exists($cfg)){
            $c=Read-SbsConfig $cfg -AllowMissing
            if($TestMode){$c.autoOpenOnStartup=$false;$c.autoExitOnDisconnect=$false;$c.cleanupSteamWindow=$false}
            [IO.File]::WriteAllText($cfg,($c|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
        }
        [void](Read-SbsConfig $cfg)
        Check-Task
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action=New-ScheduledTaskAction -Execute $exe -WorkingDirectory $Root
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
        $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $registered=$false
        try {
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            $registered=$true
        } catch {
            # Conventional per-user fallback for PCs that deny task creation.
            $w=New-Object -ComObject WScript.Shell
            $s=$w.CreateShortcut($startup);$s.TargetPath=$exe;$s.WorkingDirectory=$Root;$s.Save()
        }
        if($registered -and [IO.File]::Exists($startup)){[IO.File]::Delete($startup)}
        foreach($t in @(Owned-Tasks)){if($t.TaskName -ne $taskName){Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false}}
        # Remove only recognized shortcuts whose target/arguments belong to this app.
        $w=New-Object -ComObject WScript.Shell
        foreach($base in @([Environment]::GetFolderPath('Programs'),$programs,[Environment]::GetFolderPath('DesktopDirectory'))){
            if(![IO.Directory]::Exists($base)){continue}
            foreach($link in [IO.Directory]::GetFiles($base,'Steam Boot Switch*.lnk')){
                if($link -ieq (Join-Path $programs 'Steam Boot Switch.lnk')){continue}
                $s=$w.CreateShortcut($link)
                if(([string]$s.TargetPath).StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase) -or
                    ([string]$s.Arguments).IndexOf($Root+'\',[StringComparison]::OrdinalIgnoreCase) -ge 0){[IO.File]::Delete($link)}
            }
        }
        if(!$TestMode){
            $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamBootSwitch_v1.1_Preview'
            if(Test-Path $key){
                $old=Get-ItemProperty $key
                if($old.InstallLocation -ieq $Root){Remove-Item -LiteralPath $key -Recurse -Force}
            }
        }
        $flag=Join-Path $Root 'stop.flag';if([IO.File]::Exists($flag)){[IO.File]::Delete($flag)}
        Start-Process -FilePath $exe -ArgumentList '--monitor-only' -WorkingDirectory $Root -WindowStyle Hidden|Out-Null
        Start-Sleep -Seconds 3
        # A PC without Steam installed may validly have no active monitor.
        $running=@(Instances).Count
        [IO.File]::WriteAllText((Join-Path $Root 'installation-status.txt'),"StartupTask=$registered; MonitorProcesses=$running; Installed=$(Get-Date -Format o)")
        if($legacyRecognized){
            # Retire recognized V1 runtime only after the replacement is installed.
            $oldStartup=Join-Path ([Environment]::GetFolderPath('Startup')) 'Steam Controller Boot Mode.lnk'
            if(!$TestMode -and [IO.File]::Exists($oldStartup)){
                $w=New-Object -ComObject WScript.Shell;$link=$w.CreateShortcut($oldStartup)
                if($link.TargetPath -ieq $legacyExe){[IO.File]::Delete($oldStartup)}
            }
            foreach($name in @('SteamControllerBootMode.ps1','HiddenLauncher.cs','SteamBootHiddenLauncher-1.0.0.exe')){
                $old=Join-Path $Root $name;if([IO.File]::Exists($old)){[IO.File]::Delete($old)}
            }
        }
    } else {
        if($SettingsAction -eq 'Export' -and [IO.File]::Exists($cfg)){
            $dir=if($TestMode){$Root+'-exports'}else{[Environment]::GetFolderPath('MyDocuments')}
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::Copy($cfg,(Join-Path $dir ('SteamBootSwitch-settings-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'.json')),$false)
        }
        Stop-Owned
        foreach($t in @(Owned-Tasks)){Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop}
        if([IO.File]::Exists($startup)){
            $w=New-Object -ComObject WScript.Shell;$s=$w.CreateShortcut($startup)
            if($s.TargetPath -ieq $exe){[IO.File]::Delete($startup)}
        }
        if($SettingsAction -ne 'Keep' -and [IO.File]::Exists($cfg)){[IO.File]::Delete($cfg)}
        if($SettingsAction -ne 'Keep'){
            foreach($name in @('config.json.before-unified-settings','config.json.before-native-settings')){
                $f=Join-Path $Root $name;if([IO.File]::Exists($f)){[IO.File]::Delete($f)}
            }
        }
        foreach($name in @('stop.flag','watcher.log','watcher.log.1','watcher.log.2','installation-status.txt')){
            $f=Join-Path $Root $name;if([IO.File]::Exists($f)){[IO.File]::Delete($f)}
        }
        # Remove only recovery files created by this installer, never an arbitrary folder tree.
        $backup=Join-Path $Root 'rc1-backup'
        if([IO.Directory]::Exists($backup) -and (([IO.File]::GetAttributes($backup) -band [IO.FileAttributes]::ReparsePoint) -eq 0)){
            foreach($name in @('SteamBootSwitchNative-alpha4.exe','config.json','SteamControllerBootMode.ps1','HiddenLauncher.cs','SteamBootHiddenLauncher-1.0.0.exe')){
                $f=Join-Path $backup $name;if([IO.File]::Exists($f)){[IO.File]::Delete($f)}
            }
            if([IO.Directory]::GetFileSystemEntries($backup).Count -eq 0){[IO.Directory]::Delete($backup)}
        }
    }
    [IO.File]::WriteAllText($result,"SUCCESS: $Mode")
    exit 0
} catch {
    [IO.File]::WriteAllText($result,"FAILED: $Mode`r`n$($_.Exception.Message)")
    exit 1
}
