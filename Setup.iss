[Setup]
AppId={code:AppIdentity}
AppName=Steam Boot Switch
AppVersion=1.1.1
AppVerName=Steam Boot Switch 1.1.1
AppPublisher=Steam Boot Switch contributors
DefaultDirName={localappdata}\SteamControllerBootMode
DefaultGroupName={code:GroupName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
OutputDir=dist
OutputBaseFilename=SteamBootSwitchSetup-1.1.1
SetupIconFile=app\SteamBootSwitch.ico
UninstallDisplayIcon={app}\SteamBootSwitch.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
WizardSizePercent=130
CloseApplications=no
RestartApplications=no
LicenseFile=LICENSE
VersionInfoVersion=1.1.1.0
UsePreviousAppDir=yes
UsePreviousLanguage=no

[Files]
Source: "app\*"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "CHANGELOG.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "QA-REPORT.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\{code:GroupName}\Steam Boot Switch"; Filename: "{app}\SteamBootSwitchSettings.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\SteamBootSwitchSettings.exe"; Description: "Open Steam Boot Switch Settings"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\qa-install.marker"

[Code]
var TestInstall: Boolean;
function IsTest: Boolean;
begin
  Result := TestInstall or FileExists(ExpandConstant('{app}\qa-install.marker'));
end;
function AppIdentity(Param: String): String;
begin
  // Keep the V1.1.0 isolated test identity so this installer exercises an in-place QA upgrade.
  if TestInstall then Result := 'SteamBootSwitch_V110_QA' else Result := 'SteamBootSwitch';
end;
function GroupName(Param: String): String;
begin
  if TestInstall then Result := 'Steam Boot Switch V1.1.1 QA' else Result := 'Steam Boot Switch';
end;
// Restored 1.1.1 welcome page (originally developed for Preview 2).
// This modifies the native Inno wizard, not a separate pop-up.
procedure InitializeWizard;
var
  WelcomeText: String;
  InstallDir: String;
  ShortcutPath: String;
begin
  InstallDir := WizardDirValue;
  ShortcutPath := ExpandConstant('{userprograms}') + '\' + WizardGroupValue + '\Steam Boot Switch.lnk';
  WelcomeText :=
    'Steam Boot Switch opens and closes Steam Big Picture based on your ' +
    'controller activity, helping your home theater or living-room PC feel ' +
    'more like a console when you want it - and a regular PC when you need it.' + #13#10#13#10 +
    'Installation folder:' + #13#10 + InstallDir + #13#10#13#10 +
    'Start Menu shortcut:' + #13#10 + ShortcutPath + #13#10#13#10;
  if FileExists(AddBackslash(InstallDir) + 'config.json') then
    WelcomeText := WelcomeText +
      'Upgrading from an earlier version? Your saved settings will be kept.' + #13#10#13#10;
  WelcomeText := WelcomeText +
    'When installation finishes, Steam Boot Switch Settings will open automatically.';
  WizardForm.WelcomeLabel1.Caption := 'Welcome to Steam Boot Switch V1.1.1!';
  WizardForm.WelcomeLabel2.WordWrap := True;
  WizardForm.WelcomeLabel2.Caption := WelcomeText;
  WizardForm.WelcomeLabel2.AdjustHeight;
end;
function InitializeSetup: Boolean;
var Release: Cardinal;
begin
  TestInstall := ExpandConstant('{param:SBSTEST|0}') = '1';
  Result := RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) and (Release >= 528040);
  if not Result then MsgBox('Steam Boot Switch requires .NET Framework 4.8. Install it from Microsoft, then run Setup again.', mbError, MB_OK);
end;
function Maintain(Mode, Source, Action: String): Boolean;
var Params: String; ExitCode: Integer;
begin
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+Source+'\Maintenance.ps1" -Mode '+Mode+' -Root "'+ExpandConstant('{app}')+'" -SettingsAction '+Action;
  if IsTest then Params := Params+' -TestMode';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ExtractTemporaryFile('Maintenance.ps1');
  ExtractTemporaryFile('Settings.Core.ps1');
  ExtractTemporaryFile('LegacyUpgrade.ps1');
  ExtractTemporaryFile('recognized-engines.txt');
  if not Maintain('Preflight', ExpandConstant('{tmp}'), 'Keep') then
    Result := 'Preflight failed. No application files were replaced. Close Settings and review %TEMP%\SteamBootSwitch-Preflight-Result.txt.';
end;
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if TestInstall then SaveStringToFile(ExpandConstant('{app}\qa-install.marker'), 'QA', False);
    if not Maintain('Install', ExpandConstant('{app}'), 'Keep') then
      RaiseException('Setup copied the files, but startup configuration failed. See %TEMP%\SteamBootSwitch-Install-Result.txt. Run Setup again to repair.');
  end;
end;
function InitializeUninstall: Boolean;
var Choice: Integer; Action: String;
begin
  Action := ExpandConstant('{param:SETTINGS|Keep}');
  if not UninstallSilent then begin
    Choice := MsgBox('Export your settings to Documents before uninstalling?'+#13#10+'Yes: export and remove local settings.'+#13#10+'No: keep settings here for reinstall.'+#13#10+'Cancel: cancel uninstall.', mbConfirmation, MB_YESNOCANCEL);
    if Choice = IDCANCEL then begin Result := False; exit; end;
    if Choice = IDYES then Action := 'Export' else Action := 'Keep';
  end;
  Result := Maintain('Uninstall', ExpandConstant('{app}'), Action);
  if not Result then MsgBox('Unable to stop or remove Steam Boot Switch startup. Uninstall was canceled. See %TEMP%\SteamBootSwitch-Uninstall-Result.txt.', mbError, MB_OK);
end;
