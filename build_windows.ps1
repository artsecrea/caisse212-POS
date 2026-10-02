<#
.SYNOPSIS
  One-shot Windows release: flutter build -> caisse212.exe -> update zip -> Inno Setup installer.

.EXAMPLE
  .\build_windows.ps1                       # build the version already in pubspec.yaml
  .\build_windows.ps1 -Bump                 # patch+1 and build+1, then build
  .\build_windows.ps1 -Version 1.3.0 -Build 12
  .\build_windows.ps1 -SkipBuild            # repackage the last flutter build
  .\build_windows.ps1 -NoInstaller          # zip only

Outputs land in build\release\:
  caisse212-<ver>+<build>-windows.zip   contents at the zip root (what the updates server serves)
  caisse212-setup-<ver>.exe             installer / in-place upgrader
#>
param(
    [string]$Version,
    [int]$Build,
    [switch]$Bump,
    [switch]$SkipBuild,
    [switch]$NoZip,
    [switch]$NoInstaller
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Pubspec = Join-Path $Root 'pubspec.yaml'
$ReleaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
$OutDir = Join-Path $Root 'build\release'
$Bundle = Join-Path $OutDir 'bundle'
$FlutterExe = 'posecrea.exe'   # BINARY_NAME in windows\CMakeLists.txt
$ShipExe = 'caisse212.exe'
$Iss = Join-Path $Root 'installer\caisse212.iss'

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }

# version
$text = [IO.File]::ReadAllText($Pubspec)
$m = [regex]::Match($text, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $m.Success) { Fail "No 'version: X.Y.Z+N' line in pubspec.yaml" }
$curVersion = "$($m.Groups[1].Value).$($m.Groups[2].Value).$($m.Groups[3].Value)"
$curBuild = [int]$m.Groups[4].Value

$newVersion = $curVersion
$newBuild = $curBuild
if ($Bump) {
    $newVersion = "$($m.Groups[1].Value).$($m.Groups[2].Value).$([int]$m.Groups[3].Value + 1)"
    $newBuild = $curBuild + 1
}
if ($Version) { $newVersion = $Version }
if ($PSBoundParameters.ContainsKey('Build')) { $newBuild = $Build }
if ($newVersion -notmatch '^\d+\.\d+\.\d+$') { Fail "Version must be X.Y.Z (got '$newVersion')" }

if ($newVersion -ne $curVersion -or $newBuild -ne $curBuild) {
    if ($SkipBuild) { Fail "-SkipBuild cannot change the version: the exe would still carry $curVersion+$curBuild" }
    if ($newBuild -le $curBuild) { Fail "Build number must go up (current $curBuild, asked $newBuild) or tills will not see the update" }
    Step "pubspec.yaml: $curVersion+$curBuild -> $newVersion+$newBuild"
    $text = $text.Substring(0, $m.Index) + "version: $newVersion+$newBuild" + $text.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllText($Pubspec, $text, (New-Object Text.UTF8Encoding $false))
} else {
    Step "Version $newVersion+$newBuild"
}
$tag = "$newVersion+$newBuild"

# flutter build
if ($SkipBuild) {
    Step 'Skipping flutter build'
} else {
    # A stale Runner.res keeps the old version resource in the exe, and the app
    # reads its build number from there - so a build-number-only bump would
    # otherwise ship an exe that still reports the old build.
    $res = Join-Path $Root 'build\windows\x64\runner\posecrea.dir\Release\Runner.res'
    if (Test-Path $res) { Remove-Item $res -Force }

    Step 'flutter build windows --release'
    Push-Location $Root
    try { & flutter build windows --release } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Fail "flutter build failed (exit $LASTEXITCODE)" }
}
if (-not (Test-Path (Join-Path $ReleaseDir $FlutterExe))) { Fail "$FlutterExe not found in $ReleaseDir" }

# stage bundle with the renamed exe
Step "Staging bundle -> $Bundle"
if (Test-Path $Bundle) { Remove-Item $Bundle -Recurse -Force }
New-Item -ItemType Directory -Force $Bundle | Out-Null
# Leave out anything a dev run may have dropped next to the exe (local DB,
# logs) and any leftover caisse212.exe from an older build.
robocopy $ReleaseDir $Bundle /E /NFL /NDL /NJH /NJS /NP /XF $ShipExe '*.db' '*.db-wal' '*.db-shm' 'logs.txt' 'error_log.txt' | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy failed (exit $LASTEXITCODE)" }
Rename-Item (Join-Path $Bundle $FlutterExe) $ShipExe
$exeCount = @(Get-ChildItem $Bundle -Filter '*.exe' -File).Count
if ($exeCount -ne 1) { Fail "Bundle must hold exactly one top-level .exe (found $exeCount); the in-app updater relies on it" }

# update zip
if (-not $NoZip) {
    $zip = Join-Path $OutDir "caisse212-$tag-windows.zip"
    Step "Zipping -> $(Split-Path $zip -Leaf)"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($Bundle, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $zipInfo = Get-Item $zip
    $zipSha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
}

# installer
if (-not $NoInstaller) {
    $iscc = @(
        (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $iscc) { Fail 'Inno Setup 6 (ISCC.exe) not found - install it from https://jrsoftware.org/isdl.php' }

    # Bundled into the setup, which runs it only when the PC's runtime is older.
    $vcRedist = Join-Path $Root 'build\redist\vc_redist.x64.exe'
    if (-not (Test-Path $vcRedist)) {
        Step 'Downloading VC++ redistributable (x64)'
        New-Item -ItemType Directory -Force (Split-Path $vcRedist) | Out-Null
        Invoke-WebRequest -UseBasicParsing 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcRedist
    }
    if ((Get-AuthenticodeSignature $vcRedist).Status -ne 'Valid') {
        Remove-Item $vcRedist -Force
        Fail 'vc_redist.x64.exe has no valid signature - deleted, run again to re-download'
    }
    $vc = (Get-Item $vcRedist).VersionInfo

    Step 'Compiling installer (Inno Setup)'
    & $iscc /Q "/DAppVersion=$newVersion" "/DAppBuild=$newBuild" "/DSourceDir=$Bundle" "/DOutputDir=$OutDir" `
        "/DVcRedist=$vcRedist" "/DVcMajor=$($vc.FileMajorPart)" "/DVcMinor=$($vc.FileMinorPart)" "/DVcBld=$($vc.FileBuildPart)" $Iss
    if ($LASTEXITCODE -ne 0) { Fail "ISCC failed (exit $LASTEXITCODE)" }
    $setup = Join-Path $OutDir "caisse212-setup-$newVersion.exe"
}

# summary
Write-Host "`n[OK] CAISSE212 $tag" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  zip       $($zipInfo.FullName)"
    Write-Host "  size      $($zipInfo.Length) bytes"
    Write-Host "  sha256    $zipSha"
}
if (-not $NoInstaller) { Write-Host "  installer $setup" }
