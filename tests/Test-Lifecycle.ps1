param([string]$LegacyEngine='')
$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot 'installed'
$exe=Join-Path $root 'SteamBootSwitchNative-alpha4.exe'
$setup=Join-Path $r 'dist\SteamBootSwitchSetup-1.1.0.exe'
$task='SteamBootSwitch_V110_QA'
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SteamBootSwitch_V110_QA_is1'
$menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Steam Boot Switch V1.1.0 QA'
$cfg=Join-Path $root 'config.json'
$results=New-Object 'System.Collections.Generic.List[string]'
function Check($ok,[string]$name){if(!$ok){throw $name};$results.Add('PASS '+$name);[IO.File]::WriteAllLines(($PSScriptRoot+'\lifecycle-results.txt'),$results)}
function Processes {@(Get-CimInstance Win32_Process -Filter "Name='SteamBootSwitchNative-alpha4.exe'"|Where-Object {$_.ExecutablePath -ieq $exe})}
function Run([string]$file,[string]$arguments){$p=Start-Process $file -ArgumentList $arguments -WindowStyle Hidden -PassThru;if(!$p.WaitForExit(90000)){throw 'Child timed out'};return $p.ExitCode}
function Install([string]$label){Run $setup ('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SBSTEST=1 /DIR="'+$root+'" /LOG="'+$PSScriptRoot+'\'+$label+'.log"')}
function Uninstall([string]$action){Run ($root+'\unins000.exe') ('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SETTINGS='+$action+' /LOG="'+$PSScriptRoot+'\uninstall-'+$action+'.log"')}
try {
    if(![IO.File]::Exists($exe)){Check ((Install 'clean-install') -eq 0) 'Clean installer exits successfully'}
    Check ((Processes).Count -eq 2) 'Clean install starts native watcher and worker'
    Check ((Get-ScheduledTask -TaskName $task).Actions.Execute -ieq $exe) 'Task points to isolated watcher'
    Check ((Get-ItemProperty $key).DisplayVersion -eq '1.1.0') 'Installed Apps registration'
    Check ([IO.Directory]::GetFiles($menu,'*.lnk').Count -eq 1) 'Exactly one Start Menu application'
    Check ((Run ($env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe') ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$root+'\Settings.ps1" -SelfTest')) -eq 0) 'Installed settings entry initializes without showing a window'
    $ids=@(Processes|ForEach-Object {[int]$_.ProcessId})
    $samples=@{};foreach($id in $ids){$samples[$id]=(Get-Process -Id $id).TotalProcessorTime.TotalMilliseconds}
    $timer=[Diagnostics.Stopwatch]::StartNew();Start-Sleep -Seconds 30;$timer.Stop()
    $cpu=0;$memory=0
    foreach($id in $ids){$p=Get-Process -Id $id;$cpu+=$p.TotalProcessorTime.TotalMilliseconds-$samples[$id];$memory+=$p.WorkingSet64}
    $logical=[Environment]::ProcessorCount
    $perf=[ordered]@{seconds=$timer.Elapsed.TotalSeconds;cpuMilliseconds=$cpu;logicalProcessors=$logical;oneCorePercent=100*$cpu/$timer.Elapsed.TotalMilliseconds;machinePercent=100*$cpu/$timer.Elapsed.TotalMilliseconds/$logical;combinedWorkingSetMB=$memory/1MB;state='Idle/docked; QA actuation disabled; two native processes; UI closed';alpha42CpuPercent=0.03;alpha42WorkingSetMB=75.65}
    [IO.File]::WriteAllText(($PSScriptRoot+'\resources.json'),($perf|ConvertTo-Json))
    . ($root+'\Settings.Core.ps1')
    $base=Read-SbsConfig $cfg;$chosen=$base|ConvertTo-Json|ConvertFrom-Json;$chosen.disconnectGraceSeconds=if($base.disconnectGraceSeconds -eq 8){9}else{8}
    $save=Save-SbsConfig $cfg $base $chosen
    $message=Restart-SbsMonitor $root
    Start-Sleep -Seconds 2
    Check ($save.RestartRequired -and (Read-SbsConfig $cfg).disconnectGraceSeconds -eq $chosen.disconnectGraceSeconds -and (Processes).Count -eq 2) 'Real save/apply restarts isolated watcher'
    $saved=[IO.File]::ReadAllText($cfg)
    $w=New-Object -ComObject WScript.Shell
    $oldLink=$w.CreateShortcut($menu+'\Steam Boot Switch Settings.lnk');$oldLink.TargetPath=$root+'\SteamBootSwitchSettings.exe';$oldLink.Save()
    Check ((Install 'upgrade') -eq 0) 'RC upgrade installer exits successfully'
    Check ([IO.File]::ReadAllText($cfg) -ceq $saved) 'Upgrade preserves settings byte-for-byte'
    Check ([IO.Directory]::GetFiles($menu,'*.lnk').Count -eq 1) 'Upgrade retains one Start Menu entry'
    Check ((Uninstall 'Keep') -eq 0) 'Uninstall with settings preserved'
    Check ((Processes).Count -eq 0) 'Uninstall stops both owned processes'
    Check (!(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) 'Uninstall removes owned task'
    Check (!(Test-Path $key)) 'Uninstall removes Installed Apps registration'
    Check (![IO.File]::Exists($menu+'\Steam Boot Switch.lnk')) 'Uninstall removes Start Menu entry'
    Check ([IO.File]::ReadAllText($cfg) -ceq $saved) 'Uninstall Keep retains exact settings'
    Check ((Install 'reinstall') -eq 0) 'Reinstall without previous application files'
    Check ([IO.File]::ReadAllText($cfg) -ceq $saved) 'Reinstall uses preserved settings'
    Check ((Uninstall 'Export') -eq 0) 'Uninstall exports settings'
    Check (![IO.File]::Exists($cfg)) 'Export uninstall removes live settings'
    $exports=[IO.Directory]::GetFiles($root+'-exports','*.json')
    Check ($exports.Count -gt 0 -and [IO.File]::ReadAllText($exports[$exports.Count-1]) -ceq $saved) 'Export matches exact settings'
    if($LegacyEngine){
        [IO.File]::Copy($LegacyEngine,$exe,$true)
        [IO.File]::WriteAllText($cfg,$saved)
        Check ((Install 'legacy-upgrade') -eq 0) 'Recognized previous native build upgrade'
        Check ([IO.File]::ReadAllText($cfg) -ceq $saved) 'Legacy upgrade retains settings'
        Check ((Get-FileHash $exe).Hash -eq (Get-FileHash ($r+'\app\SteamBootSwitchNative-alpha4.exe')).Hash) 'Legacy engine replaced by rebuilt V1.1.0'
        Check ((Uninstall 'Delete') -eq 0) 'Explicit silent delete-settings uninstall'
    }
    [IO.File]::WriteAllText($exe,'unknown executable fixture')
    Check ((Install 'unknown-refused') -ne 0) 'Unknown watcher refused'
    Check ([IO.File]::ReadAllText($exe) -ceq 'unknown executable fixture') 'Unknown watcher left untouched'
    [IO.File]::Delete($exe)
    [IO.File]::WriteAllText($cfg,'{"startupWindowSeconds":0}')
    Check ((Install 'invalid-refused') -ne 0) 'Invalid settings refused before replacement'
    Check (![IO.File]::Exists($exe)) 'Failed preflight installs no watcher'
    [IO.File]::Delete($cfg)
    $collision=New-ScheduledTaskAction -Execute ($env:WINDIR+'\System32\notepad.exe')
    Register-ScheduledTask -TaskName $task -Action $collision -Force|Out-Null
    try {
        Check ((Install 'task-collision-refused') -ne 0) 'Unrelated task name collision refused'
        Check ((Get-ScheduledTask -TaskName $task).Actions.Execute -like '*notepad.exe') 'Unrelated task left untouched'
    } finally {Unregister-ScheduledTask -TaskName $task -Confirm:$false}
    Check ((Install 'final-clean') -eq 0) 'Fresh defaults install after complete removal'
    Check ((Uninstall 'Delete') -eq 0) 'Final QA cleanup'
    Check ((Processes).Count -eq 0 -and !(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) 'No test processes or task remain'
    Check (![IO.Directory]::Exists($root+'\rc1-backup')) 'Installer recovery executables removed on uninstall'
} catch {$results.Add('FAIL '+$_);[IO.File]::WriteAllLines(($PSScriptRoot+'\lifecycle-results.txt'),$results);exit 1}
