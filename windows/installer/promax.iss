#if VER < EncodeVer(6, 3, 0)
  #error Inno Setup 6.3 or newer is required to compile this script
#endif

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppBuild
  #define AppBuild "0"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{8C6F2C0E-5B7A-4D41-9F3E-2B7C1A9D4E61}
AppName=ProMax
AppVersion={#AppVersion}
AppVerName=ProMax {#AppVersion}
AppPublisher=ProMax
AppPublisherURL=https://github.com/stillemptyNOW/ProMax
AppSupportURL=https://github.com/stillemptyNOW/ProMax/issues
AppUpdatesURL=https://github.com/stillemptyNOW/ProMax/releases
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoProductName=ProMax
VersionInfoDescription=ProMax Setup
DefaultDirName={autopf}\ProMax
DefaultGroupName=ProMax
DisableProgramGroupPage=yes
DisableDirPage=auto
DisableReadyPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=ProMax-Setup-{#AppVersion}-{#AppBuild}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ProMax.exe
UninstallDisplayName=ProMax
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
#if VER >= EncodeVer(6, 5, 2)
WizardImageFile=wizard_image_100.png,wizard_image_150.png,wizard_image_200.png
WizardSmallImageFile=wizard_small_100.png,wizard_small_150.png,wizard_small_200.png
#endif
SetupMutex=ProMaxSetup
CloseApplications=force
RestartApplications=no
UsePreviousTasks=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\ProMax"; Filename: "{app}\ProMax.exe"
Name: "{autodesktop}\ProMax"; Filename: "{app}\ProMax.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ProMax.exe"; Description: "{cm:LaunchProgram,ProMax}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\ProMax.exe"; Flags: nowait skipifnotsilent runasoriginaluser; Check: RelaunchRequested

[Code]
function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
