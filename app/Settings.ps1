param([switch]$Installer,[string]$OutputPath='', [switch]$SelfTest)
# Entry point for the 1.1 native-launcher / WPF settings surface.
# The native monitoring executable and controller logic are untouched.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$root=$PSScriptRoot
$core=Join-Path $PSScriptRoot 'Settings.Core.ps1'
if(-not [IO.File]::Exists($core)){$core=Join-Path $root 'Settings.Core.ps1'}
. $core
. (Join-Path $PSScriptRoot 'Settings.View.ps1')
$path=Join-Path $root 'config.json'
try {$baseline=Read-SbsConfig $path -AllowMissing:$Installer}
catch {
    if($SelfTest){Write-Error ('Settings load failed: ' + $_.Exception.Message);exit 1}
    [void][System.Windows.MessageBox]::Show('Cannot load current settings. No files have been changed.'+[Environment]::NewLine+$_.Exception.Message,'Steam Boot Switch','OK','Error')
    exit 1
}
try{$view=New-SbsSettingsView $baseline ([bool]$Installer)}
catch{
    if($SelfTest){Write-Error ('Settings UI creation failed: ' + $_.Exception.Message);exit 1}
    [void][System.Windows.MessageBox]::Show('Unable to create the settings window:'+[Environment]::NewLine+$_.Exception.Message,'Steam Boot Switch','OK','Error')
    exit 1
}
if($SelfTest) {
    if(@($view.Controls.Keys).Count -lt 20) { Write-Error 'UI controls did not initialize';exit 1 }
    $view.Window.Close()
    exit 0
}
$view.Save.Add_Click({
    $view.Save.IsEnabled=$false
    $view.Window.Cursor=[Windows.Input.Cursors]::Wait
    $saved=$false
    try {
        $chosen=Get-SbsViewChoices $view
        $destination=if($OutputPath){[IO.Path]::GetFullPath($OutputPath)}else{$path}
        if($OutputPath -and $destination -ine [IO.Path]::GetFullPath($path)) {
            $export=$baseline | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            foreach($key in $script:SbsDefaults.Keys){$export.$key=$chosen.$key}
            Assert-SbsConfig $export
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [IO.File]::WriteAllText($destination,($export | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
            $message='Choices saved for installation.'
        } else {
            $result=Save-SbsConfig $destination $baseline $chosen -AllowCreate:$Installer
            $saved=$true
            if($result.Changed.Count -eq 0){$message='No changes were needed.'}
            elseif($Installer){$message='Choices saved for installation.'}
            elseif($result.RestartRequired){$message=Restart-SbsMonitor $root}
            else{$message='Saved. Undock changes apply after the next status refresh; re-dock before testing.'}
        }
        if(!$Installer){[void][System.Windows.MessageBox]::Show($view.Window,$message,'Steam Boot Switch','OK','Information')}
        $view.Window.DialogResult=$true
    } catch {
        $title=if($saved){'Settings saved; restarting monitor needs attention'}else{'Settings were not saved'}
        [void][System.Windows.MessageBox]::Show($view.Window,$_.Exception.Message,$title,'OK','Warning')
        if($saved){$view.Window.DialogResult=$true}
    } finally {
        $view.Save.IsEnabled=$true
        $view.Window.Cursor=$null
    }
})
$result=$view.Window.ShowDialog()
if($result -eq $true){exit 0}else{exit 2}
