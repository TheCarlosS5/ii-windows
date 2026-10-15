; ii-windows setup: the "next, accept, install" wizard. It wraps the package folder (install.ps1 + app\) that
; tools\package\make-package.ps1 builds: the wizard asks the questions, unpacks the package to a temporary folder
; and runs install.ps1 -Yes with the matching switches (the same installer that always did the real work: copies
; the runtime, exports the registry keys it touches, writes install.json for the uninstaller, makes the shortcuts).
; Build:  tools\package\make-setup.ps1   (needs Inno Setup 6: winget install JRSoftware.InnoSetup)
;
#ifndef SourceDir
  #error Pass /DSourceDir=<package folder> (make-setup.ps1 does)
#endif
#ifndef AppVersion
  #define AppVersion "0.2.0"
#endif
#ifndef RepoRoot
  #define RepoRoot ".."
#endif

[Setup]
AppId={{9F3C2B71-6D1E-4C58-A3B0-5E7D2C94F1A6}
AppName=ii-windows
AppVersion={#AppVersion}
AppVerName=ii-windows {#AppVersion}
AppPublisher=Carlos (TheCarlosS5)
AppPublisherURL=https://github.com/TheCarlosS5/ii-windows
AppSupportURL=https://github.com/TheCarlosS5/ii-windows/issues
AppUpdatesURL=https://github.com/TheCarlosS5/ii-windows/releases
; The real installation is install.ps1's (per user, with its own entry in Settings > Apps and its own uninstaller).
DefaultDirName={tmp}\ii-windows-setup
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir={#RepoRoot}\out
OutputBaseFilename=ii-windows-Setup-{#AppVersion}
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
WizardImageFile={#RepoRoot}\tools\package\setup\wizard.bmp
WizardSmallImageFile={#RepoRoot}\tools\package\setup\wizard-small.bmp
LicenseFile={#RepoRoot}\LICENSE
SetupIconFile={#RepoRoot}\tools\package\setup\ii.ico
ShowLanguageDialog=auto
CloseApplications=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
es.WelcomeBody=Este asistente instala ii-windows: una barra superior, un dock con efecto lupa, paneles laterales, buscador estilo GNOME y widgets en el escritorio, sobre Windows 11.%n%nNo se modifican archivos del sistema ni se necesitan permisos de administrador. Todo lo que se cambia queda anotado y se puede deshacer: desde el menú Inicio (Desinstalar ii-windows), con Ctrl+Alt+Mayús+R, o con "Rescate de ii".%n%nCierra los programas que estés usando antes de continuar.
en.WelcomeBody=This wizard installs ii-windows: a top bar, a dock with a magnifying effect, side panels, a GNOME-style search and desktop widgets on top of Windows 11.%n%nNo system files are modified and no administrator rights are needed. Everything that changes is noted and can be undone: from the Start menu (Uninstall ii-windows), with Ctrl+Alt+Shift+R, or with "Rescue ii".%n%nClose the programs you are using before continuing.
es.TaskAutostart=Iniciar ii-windows al iniciar sesión en Windows
en.TaskAutostart=Start ii-windows when I sign in to Windows
es.TaskCursor=Usar el cursor Bibata (se restaura el actual al desinstalar)
en.TaskCursor=Use the Bibata cursor (the current one is restored on uninstall)
es.TaskFastfetch=Añadir el comando "fastfetch" al terminal
en.TaskFastfetch=Add the "fastfetch" command to the terminal
es.GroupOptions=Opciones:
en.GroupOptions=Options:
es.Installing=Instalando ii-windows (la primera vez puede tardar un minuto)...
en.Installing=Installing ii-windows (the first time can take a minute)...
es.Failed=La instalación no terminó bien.%n%nNo se ha dejado nada a medias: puedes volver a ejecutar este instalador. El detalle está en:%n%1%n%nSi el problema sigue, abre una incidencia con ese archivo.
en.Failed=The installation did not finish.%n%nNothing was left half-done: you can run this installer again. The details are in:%n%1%n%nIf the problem continues, open an issue with that file.
es.NeedWin11=ii-windows necesita Windows 11 (compilación 22000 o superior).
en.NeedWin11=ii-windows needs Windows 11 (build 22000 or later).
es.StartNow=Iniciar ii ahora
en.StartNow=Start ii now
es.FinishNote=ii-windows está instalado. Si algo no te gusta, Ctrl+Alt+Mayús+R devuelve la barra de tareas de Windows al instante.
en.FinishNote=ii-windows is installed. If something is not to your liking, Ctrl+Alt+Shift+R gives Windows' taskbar back at once.

[Tasks]
Name: "autostart"; Description: "{cm:TaskAutostart}"; GroupDescription: "{cm:GroupOptions}"
Name: "cursor"; Description: "{cm:TaskCursor}"; GroupDescription: "{cm:GroupOptions}"
Name: "fastfetch"; Description: "{cm:TaskFastfetch}"; GroupDescription: "{cm:GroupOptions}"

[Files]
; The whole package folder, unpacked to the temporary folder and removed afterwards.
Source: "{#SourceDir}\*"; DestDir: "{tmp}\ii-package"; Flags: recursesubdirs createallsubdirs ignoreversion deleteafterinstall

[Run]
Filename: "{userappdata}\Microsoft\Windows\Start Menu\Programs\ii-windows\Iniciar ii.lnk"; Description: "{cm:StartNow}"; Flags: postinstall shellexec nowait skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := Version.Build >= 22000;
  if not Result then
    MsgBox(CustomMessage('NeedWin11'), mbCriticalError, MB_OK);
end;

procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel2.Caption := CustomMessage('WelcomeBody');
  WizardForm.FinishedLabel.Caption := CustomMessage('FinishNote');
end;

function LogPath(): String;
begin
  Result := ExpandConstant('{localappdata}\ii-windows\install.log');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Args: String;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := CustomMessage('Installing');
    WizardForm.FilenameLabel.Caption := '';
    ForceDirectories(ExpandConstant('{localappdata}\ii-windows'));
    Args := '/c powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\ii-package\install.ps1') + '" -Yes';
    if not WizardIsTaskSelected('autostart') then Args := Args + ' -NoAutostart';
    if not WizardIsTaskSelected('cursor') then Args := Args + ' -NoCursor';
    if not WizardIsTaskSelected('fastfetch') then Args := Args + ' -NoFastfetch';
    // For tests: setup.exe /SANDBOX=1 installs only files (install.ps1 -Sandbox) into the folders LOCALAPPDATA/APPDATA point to.
    if ExpandConstant('{param:SANDBOX|0}') = '1' then Args := Args + ' -Sandbox';
    Args := Args + ' > "' + LogPath() + '" 2>&1';
    if (not Exec(ExpandConstant('{cmd}'), Args, ExpandConstant('{tmp}\ii-package'), SW_HIDE, ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
    begin
      MsgBox(FmtMessage(CustomMessage('Failed'), [LogPath()]), mbError, MB_OK);
      Abort;
    end;
  end;
end;
