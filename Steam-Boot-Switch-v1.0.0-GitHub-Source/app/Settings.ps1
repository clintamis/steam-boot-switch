param([switch]$Installer, [string]$OutputPath = '')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$folder=Join-Path $env:LOCALAPPDATA 'SteamControllerBootMode'
$configPath=Join-Path $folder 'config.json'
$cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.default.json') -Raw | ConvertFrom-Json
if (Test-Path -LiteralPath $configPath) {
    try {
        $old=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        foreach ($p in $old.PSObject.Properties) {
            if ($null -ne $cfg.PSObject.Properties[$p.Name]) { $cfg.($p.Name)=$p.Value }
        }
    } catch { [void][System.Windows.Forms.MessageBox]::Show('Existing preferences could not be read. Defaults are shown.','Steam Boot Switch') }
}
$form=New-Object System.Windows.Forms.Form
$form.Text=if($Installer){'Steam Boot Switch v1.0.0 - Install or Upgrade'}else{'Steam Boot Switch - Settings'}
$form.ClientSize=New-Object System.Drawing.Size(600,554)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false; $form.MinimizeBox=$false
$form.Font=New-Object System.Drawing.Font('Segoe UI',9)
function Label([string]$s,[int]$x,[int]$y,[int]$w=555,[int]$h=22) {
    $l=New-Object System.Windows.Forms.Label; $l.Text=$s
    $l.Location=New-Object System.Drawing.Point($x,$y); $l.Size=New-Object System.Drawing.Size($w,$h)
    $form.Controls.Add($l); return $l
}
function Check([string]$s,[int]$y,[bool]$v) {
    $c=New-Object System.Windows.Forms.CheckBox; $c.Text=$s; $c.Checked=$v
    $c.Location=New-Object System.Drawing.Point(22,$y); $c.Size=New-Object System.Drawing.Size(552,25)
    $form.Controls.Add($c); return $c
}
function Edit([string]$s,[int]$x,[int]$y,[int]$w) {
    $t=New-Object System.Windows.Forms.TextBox; $t.Text=$s
    $t.Location=New-Object System.Drawing.Point($x,$y); $t.Size=New-Object System.Drawing.Size($w,25)
    $form.Controls.Add($t); return $t
}
$head=Label 'Steam Boot Switch' 20 13 565 32
$head.Font=New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
[void](Label 'Big Picture auto-open at startup and auto-close on disconnect.' 22 50 548 25)
$auto=Check 'Exit Big Picture if the last controller disconnects' 89 ([bool]$cfg.autoExitOnDisconnect)
[void](Label 'Wait after disconnection (seconds):' 43 122 275 24)
$delay=Edit ([string]$cfg.disconnectGraceSeconds) 331 119 94
[void](Label '1 or more' 437 122 110 25)
$cancel=Check 'Cancel the exit if I move the mouse or use the keyboard' 156 ([bool]$cfg.mouseActivityCancelsExit)
[void](Label 'Games always block automatic exit. Firmware updates may also disconnect controllers.' 43 186 525 36)
$cleanup=Check 'Console-style: hide Steam desktop window after Big Picture' 225 ([bool]$cfg.cleanupSteamWindow)
$prehide=Check 'Smooth transitions: pre-hide Steam desktop behind Big Picture' 257 ([bool]$cfg.preHideSteamDesktop)
# Steam handles Guide/Home button presses itself. Window visibility can affect focus,
# but we do not promise a precise one-press/two-press mode.
$helpTips=New-Object System.Windows.Forms.ToolTip
$helpTips.SetToolTip($cleanup, 'Checked = Steam stays in its tray after Big Picture; unchecked = leave desktop Steam visible. This may change how Steam handles Home/Guide focus, but the button itself is controlled by Steam.')
$helpTips.SetToolTip($prehide, 'Hide the separate Steam desktop window while Big Picture is opening or already visible. Has no effect if console-style hiding is disabled.')
[void](Label 'Window size after exit:' 44 302 180 26)
$size=New-Object System.Windows.Forms.ComboBox
$size.DropDownStyle='DropDownList'; $size.Location=New-Object System.Drawing.Point(226,299)
$size.Size=New-Object System.Drawing.Size(161,25)
[void]$size.Items.AddRange([object[]]@('Preserve','Maximize','Custom'))
$size.SelectedItem=[string]$cfg.windowSizeMode
if($size.SelectedIndex -lt 0){$size.SelectedIndex=0}
$form.Controls.Add($size)
[void](Label 'Custom width / height:' 44 337 178 24)
$w=Edit ([string]$cfg.windowWidth) 226 334 75
$h=Edit ([string]$cfg.windowHeight) 311 334 75
$size.Add_SelectedIndexChanged({$w.Enabled=($size.SelectedItem -eq 'Custom');$h.Enabled=$w.Enabled})
$w.Enabled=($size.SelectedItem -eq 'Custom');$h.Enabled=$w.Enabled
[void](Label 'Desktop cleanup delay (ms):' 44 375 235 25)
$cleanupDelay=Edit ([string]$cfg.cleanupDelayMs) 278 371 96
[void](Label '0 = immediate' 390 375 175 23)
[void](Label 'Controller detection window after sign-in (seconds):' 44 411 383 26)
$startup=Edit ([string]$cfg.startupWindowSeconds) 436 407 92
$tipText = if ($Installer -and (Test-Path -LiteralPath (Join-Path $folder 'SteamControllerBootMode.ps1'))) {
    'Upgrade detected. Steam must start with Windows. Home/Guide button behavior is controlled by Steam.'
} else { 'For PCs used as both a console and a desktop. Steam must start with Windows.' }
$tip=Label $tipText 22 445 552 39
$tip.ForeColor=[System.Drawing.Color]::DimGray
$save=New-Object System.Windows.Forms.Button
$save.Text=if($Installer){'Install / Upgrade'}else{'Save'}
$save.Location=New-Object System.Drawing.Point(382,503);$save.Size=New-Object System.Drawing.Size(91,32)
$form.Controls.Add($save)
$cancelBtn=New-Object System.Windows.Forms.Button
$cancelBtn.Text='Cancel';$cancelBtn.Location=New-Object System.Drawing.Point(483,503)
$cancelBtn.Size=New-Object System.Drawing.Size(91,32);$form.Controls.Add($cancelBtn)
$form.AcceptButton=$save;$form.CancelButton=$cancelBtn
$save.Add_Click({
    $grace=0L;$up=0L;$cd=0L;$cw=0L;$ch=0L
    if (-not [long]::TryParse($delay.Text,[ref]$grace) -or $grace -lt 1 -or $grace -gt [int]::MaxValue) {
        [void][System.Windows.Forms.MessageBox]::Show('Disconnect delay must be a whole number of seconds, 1 or greater.','Invalid setting'); return
    }
    if (-not [long]::TryParse($startup.Text,[ref]$up) -or $up -lt 15 -or $up -gt 600) {
        [void][System.Windows.Forms.MessageBox]::Show('Startup detection must be between 15 and 600 seconds.','Invalid setting'); return
    }
    if (-not [long]::TryParse($cleanupDelay.Text,[ref]$cd) -or $cd -lt 0 -or $cd -gt 3000) {
        [void][System.Windows.Forms.MessageBox]::Show('Cleanup delay must be between 0 and 3000 milliseconds.','Invalid setting'); return
    }
    if (-not [long]::TryParse($w.Text,[ref]$cw) -or -not [long]::TryParse($h.Text,[ref]$ch) -or
        $cw -lt 640 -or $cw -gt 7680 -or $ch -lt 480 -or $ch -gt 4320) {
        [void][System.Windows.Forms.MessageBox]::Show('Width must be 640-7680 and height 480-4320.','Invalid setting'); return
    }
    $script:chosen=[pscustomobject]@{
        startupWindowSeconds=[int]$up;disconnectGraceSeconds=[int]$grace
        autoExitOnDisconnect=[bool]$auto.Checked
        mouseActivityCancelsExit=[bool]$cancel.Checked
        cleanupSteamWindow=[bool]$cleanup.Checked
        preHideSteamDesktop=[bool]$prehide.Checked
        cleanupDelayMs=[int]$cd;windowSizeMode=[string]$size.SelectedItem
        windowWidth=[int]$cw;windowHeight=[int]$ch
    }
    $form.DialogResult=[System.Windows.Forms.DialogResult]::OK;$form.Close()
})
$cancelBtn.Add_Click({$form.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;$form.Close()})
if($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){ exit 2 }
$destination = if ($OutputPath) { $OutputPath } else { $configPath }
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
$script:chosen|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $destination -Encoding UTF8
if(!$Installer){[void][System.Windows.Forms.MessageBox]::Show('Saved. Sign out and back in to apply changes.','Steam Boot Switch')}
exit 0
