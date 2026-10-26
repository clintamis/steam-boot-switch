$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
. ($r+'\app\Settings.Core.ps1')
. ($r+'\app\Settings.View.ps1')
$dir=Join-Path $PSScriptRoot ('settings-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$path=Join-Path $dir 'config.json'
$passed=New-Object 'System.Collections.Generic.List[string]'
function Check($ok,[string]$name){if(!$ok){throw $name};$passed.Add('PASS '+$name)}
function Clone($c){$c|ConvertTo-Json -Depth 100|ConvertFrom-Json}
try {
    $text='{"autoPowerOffOnDock":true,"undockBigPictureMode":"Disabled","windowSizeMode":"Maximize","futureOption":{"keep":"yes"}}'
    [IO.File]::WriteAllText($path,$text)
    $base=Read-SbsConfig $path
    Check ($script:SbsDefaults.Count -eq 13) '13 configuration fields'
    $save=Save-SbsConfig $path $base (Clone $base)
    Check ($save.Changed.Count -eq 0 -and [IO.File]::ReadAllText($path) -ceq $text) 'No-op preserves exact bytes'
    $view=New-SbsSettingsView $base
    try {
        $round=Get-SbsViewChoices $view
        foreach($key in $script:SbsDefaults.Keys){Check ($round.$key -ceq $base.$key) ('UI roundtrip '+$key)}
        $view.Controls.autoOpenOnStartup.IsChecked=$false
        Check (!$view.Controls.startupWindowSeconds.IsEnabled) 'Startup control dependency'
        $view.Controls.windowSizeMode.SelectedIndex=2
        Check ($view.Controls.windowWidth.IsEnabled) 'Custom dimensions dependency'
        foreach($i in 0,1,2){$view.Controls.undockBigPictureMode.SelectedIndex=$i;Check ((Get-SbsViewChoices $view).undockBigPictureMode -ceq @('Disabled','OnConnection','Immediate')[$i]) ('Undock mapping '+$i)}
        $view.Controls.startupWindowSeconds.Text='bad'
        $threw=$false;try{Get-SbsViewChoices $view|Out-Null}catch{$threw=$true};Check $threw 'UI rejects invalid numeric input'
        # Render layout without creating/showing a desktop window.
        $view.Controls.startupWindowSeconds.Text='120'
        foreach($page in @('Startup','Picture','Desktop')){
            foreach($p in @('Startup','Picture','Desktop')){$view.Controls["Page$p"].Visibility=if($p -eq $page){'Visible'}else{'Collapsed'}}
            $surface=$view.Window.Content
            $surface.Measure((New-Object Windows.Size(1040,740)))
            $surface.Arrange((New-Object Windows.Rect(0,0,1040,740)))
            $surface.UpdateLayout()
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1040,740,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($surface)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Create((Join-Path $PSScriptRoot ($page+'.png')))
            try{$encoder.Save($stream)}finally{$stream.Dispose()}
        }
        Check $true 'Three pages laid out and rendered without showing windows'
    } finally {$view.Window.Close()}
    Check ([IO.File]::ReadAllText($path) -ceq $text) 'Closing UI does not save'
    $chosen=Clone $base;$chosen.undockBigPictureMode='OnConnection'
    $save=Save-SbsConfig $path $base $chosen
    Check (!$save.RestartRequired -and (Read-SbsConfig $path).futureOption.keep -eq 'yes') 'Hot reload and unknown fields preserved'
    Check ([IO.File]::ReadAllText($path+'.before-unified-settings') -ceq $text) 'Exact original backup'
    $base=Read-SbsConfig $path;$chosen=Clone $base;$chosen.autoOpenOnStartup=$false
    $external=Clone $base;$external.disconnectGraceSeconds=9
    [IO.File]::WriteAllText($path,($external|ConvertTo-Json -Depth 100))
    $save=Save-SbsConfig $path $base $chosen
    Check ($save.RestartRequired -and (Read-SbsConfig $path).disconnectGraceSeconds -eq 9) 'Merge unrelated external edits'
    $base=Read-SbsConfig $path;$chosen=Clone $base;$chosen.disconnectGraceSeconds=7
    $external=Clone $base;$external.disconnectGraceSeconds=11
    $text=$external|ConvertTo-Json -Depth 100;[IO.File]::WriteAllText($path,$text)
    $threw=$false;try{Save-SbsConfig $path $base $chosen|Out-Null}catch{$threw=$true}
    Check ($threw -and [IO.File]::ReadAllText($path) -ceq $text) 'Conflicting edit refused'
    $base=Read-SbsConfig $path;$chosen=Clone $base;$chosen.autoPowerOffOnDock=$false
    $lock=[IO.File]::Open($path,'Open','Read','Read')
    try{$threw=$false;try{Save-SbsConfig $path $base $chosen|Out-Null}catch{$threw=$true};Check $threw 'Locked file save refused'}finally{$lock.Dispose()}
    Check ([IO.Directory]::GetFiles($dir,'*.tmp').Count -eq 0) 'No temporary files after failure'
    foreach($bad in @('{broken','null','[]','{"autoPowerOffOnDock":"false"}','{"startupWindowSeconds":2}','{"undockBigPictureMode":"Unknown"}')){
        [IO.File]::WriteAllText($path,$bad);$threw=$false;try{Read-SbsConfig $path|Out-Null}catch{$threw=$true};Check $threw ('Reject invalid config '+$bad)
    }
    [IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'settings-results.txt'),$passed)
} catch {[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'settings-results.txt'),@($passed)+('FAIL '+$_));exit 1}
