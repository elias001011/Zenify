#define MyAppName "Zenify"
#define MyAppPublisher "Zenify Contributors"
#define MyAppExeName "zenify.exe"
#define MyAppUserModelID "io.github.elias001011.zenify"
#define MyAppVersion GetEnv("ZENIFY_VERSION")
#define RepoRoot "..\..\.."

[Setup]
AppId={{15A7A56C-610A-462A-9210-1DFA1036E882}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=no
CloseApplications=yes
RestartApplications=no
AppMutex=ZenifyDataInUse
OutputDir={#RepoRoot}\build\desktop-artifacts
OutputBaseFilename=Zenify-windows-x64-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#RepoRoot}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; AppUserModelID: "{#MyAppUserModelID}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; AppUserModelID: "{#MyAppUserModelID}"; Tasks: desktopicon

[UninstallDelete]
Type: files; Name: "{app}\install-config.txt"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  ConfigFileName = 'install-config.txt';

var
  LocationsPage: TInputDirWizardPage;
  LocationsConfirmed: Boolean;
  PreviousDataDir, PreviousDownloadsDir, PreviousMigrationSource: String;

function ConfigPath: String;
begin
  Result := AddBackslash(WizardDirValue) + ConfigFileName;
end;

function ReadConfigValue(const Key: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  if LoadStringsFromFile(ConfigPath, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos(Key + '=', Lines[I]) = 1 then
        Result := Trim(Copy(Lines[I], Length(Key) + 2, MaxInt));
end;

function IsAbsolutePath(const Path: String): Boolean;
begin
  Result := (Copy(Path, 1, 2) = '\\') or
    ((Length(Path) >= 3) and (Path[2] = ':') and ((Path[3] = '\') or (Path[3] = '/')));
end;

procedure InitializeWizard;
begin
  // Capture the previous install before the user changes the executable folder.
  PreviousDataDir := GetPreviousData('DataDir', ReadConfigValue('dataDir'));
  PreviousDownloadsDir := GetPreviousData('DownloadsDir', ReadConfigValue('downloadsDir'));
  PreviousMigrationSource := GetPreviousData('MigrationSource', ReadConfigValue('previousDataDir'));
  if PreviousDataDir = '' then
    PreviousDataDir := ExpandConstant('{userappdata}\io.github.elias001011\Zenify');
  LocationsPage := CreateInputDirPage(wpSelectDir,
    'Data locations',
    'Where should Zenify keep your data?',
    'Application data holds playlists, liked songs, history and settings. ' +
    'Downloads holds saved music and artwork. Leave a field empty to use the default. ' +
    'Avoid folders synced by OneDrive or similar services. ' +
    'Existing data is copied to a new data folder and the original is kept.',
    False, '');
  LocationsPage.Add('Application data folder (playlists, history and settings):');
  LocationsPage.Add('Downloads folder:');
  LocationsPage.Values[0] := ExpandConstant('{param:DATADIR|}');
  LocationsPage.Values[1] := ExpandConstant('{param:DOWNLOADSDIR|}');
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = LocationsPage.ID) and not LocationsConfirmed then
  begin
    if LocationsPage.Values[0] = '' then
      LocationsPage.Values[0] := PreviousDataDir;
    if LocationsPage.Values[0] = '' then
      LocationsPage.Values[0] := ExpandConstant('{userappdata}\io.github.elias001011\Zenify');
    if LocationsPage.Values[1] = '' then
      LocationsPage.Values[1] := PreviousDownloadsDir;
    if LocationsPage.Values[1] = '' then
      LocationsPage.Values[1] := ExpandConstant('{userappdata}\io.github.elias001011\Zenify\downloads');
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if WizardSilent then Exit;
  if CurPageID = LocationsPage.ID then
  begin
    for I := 0 to 1 do
    begin
      LocationsPage.Values[I] := Trim(LocationsPage.Values[I]);
      if (LocationsPage.Values[I] <> '') and not IsAbsolutePath(LocationsPage.Values[I]) then
      begin
        MsgBox('Enter a full folder path such as D:\Zenify, or leave the field empty.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end;
    if (LocationsPage.Values[0] <> PreviousDataDir) and
       (FileExists(AddBackslash(LocationsPage.Values[0]) + 'user.hive') or
        FileExists(AddBackslash(LocationsPage.Values[0]) + 'settings.hive')) then
    begin
      if MsgBox('This folder already contains application data. Zenify will use it without overwriting it. Continue?', mbConfirmation, MB_YESNO) <> IDYES then
      begin
        Result := False;
        Exit;
      end;
    end;
    if (Pos('onedrive', Lowercase(LocationsPage.Values[0])) > 0) or
       (Pos('dropbox', Lowercase(LocationsPage.Values[0])) > 0) then
    begin
      if MsgBox('This data folder appears to be cloud-synchronized. Concurrent syncing can damage the library. Use this folder anyway?', mbConfirmation, MB_YESNO) <> IDYES then
      begin
        Result := False;
        Exit;
      end;
    end;
    LocationsConfirmed := True;
  end;
end;

procedure ResolveLocations(var DataDir, DownloadsDir: String);
begin
  if LocationsConfirmed then
  begin
    DataDir := LocationsPage.Values[0];
    DownloadsDir := LocationsPage.Values[1];
  end
  else
  begin
    DataDir := Trim(ExpandConstant('{param:DATADIR|}'));
    DownloadsDir := Trim(ExpandConstant('{param:DOWNLOADSDIR|}'));
    if DataDir = '' then DataDir := PreviousDataDir;
    if DownloadsDir = '' then DownloadsDir := PreviousDownloadsDir;
  end;
end;

function MigrationSource(const DataDir: String): String;
begin
  if DataDir = PreviousDataDir then Result := PreviousMigrationSource
  else Result := PreviousDataDir;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Lines: TArrayOfString;
  DataDir, DownloadsDir: String;
begin
  if CurStep <> ssPostInstall then Exit;
  ResolveLocations(DataDir, DownloadsDir);
  SetArrayLength(Lines, 3);
  Lines[0] := 'dataDir=' + DataDir;
  Lines[1] := 'downloadsDir=' + DownloadsDir;
  Lines[2] := 'previousDataDir=' + MigrationSource(DataDir);
  if not SaveStringsToUTF8File(ConfigPath, Lines, False) then
    RaiseException('Could not save Zenify data locations.');
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
var
  DataDir, DownloadsDir: String;
begin
  ResolveLocations(DataDir, DownloadsDir);
  SetPreviousData(PreviousDataKey, 'DataDir', DataDir);
  SetPreviousData(PreviousDataKey, 'DownloadsDir', DownloadsDir);
  SetPreviousData(PreviousDataKey, 'MigrationSource', MigrationSource(DataDir));
end;
