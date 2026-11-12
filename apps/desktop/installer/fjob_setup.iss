; 今日又白干 PC 伴生端安装包。
; 当前用户安装（%LOCALAPPDATA%\Programs\FJOB），无需管理员；卸载只移除程序，
; 账本数据保留在 %APPDATA%\FJOB。
; 版本号可由 CI 覆盖：ISCC.exe /DAppVersion=0.1.1 fjob_setup.iss

#ifndef AppVersion
  #define AppVersion "0.1.1"
#endif

#define AppName "今日又白干"
#define AppExe "todayagain_desktop.exe"
#define AppPublisher "wacilimonster-source"
#define AppUrl "https://github.com/wacilimonster-source/fjob"
#define BuildDir "..\build\windows\x64\runner\Release"
#define OutputDir "..\build\installer"

[Setup]
; Stable AppId: upgrades replace the previous install, uninstall removes it.
AppId={{6C0B4B7E-7A1C-4F53-9E4A-2B7D5C8F1A30}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={localappdata}\Programs\FJOB
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=FJOB-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent
