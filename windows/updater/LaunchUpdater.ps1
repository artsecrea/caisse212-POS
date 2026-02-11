# Windows Updater Launcher
# This is a simplified launcher that can be called from Flutter

param(
    [Parameter(Mandatory=$true)]
    [string]$UpdatePackagePath,

    [Parameter(Mandatory=$false)]
    [string]$Checksum = ""
)

# Get the current directory (app directory)
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UpdaterScript = Join-Path $AppDir "updater\WindowsUpdater.ps1"

# Check if updater script exists
if (-not (Test-Path $UpdaterScript)) {
    Write-Host "ERROR: Updater script not found at: $UpdaterScript" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Get executable name (assume main .exe in current directory)
$Executable = Get-ChildItem -Path $AppDir -Filter "*.exe" | Select-Object -First 1

if ($null -eq $Executable) {
    Write-Host "ERROR: No executable found in app directory" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$ExecutableName = $Executable.Name

# Build arguments
$Arguments = @(
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$UpdaterScript`"",
    "-DownloadUrl", "`"file:///$UpdatePackagePath`"",
    "-AppDirectory", "`"$AppDir`"",
    "-ExecutableName", "`"$ExecutableName`"",
    "-ExcludeFolders", "@('logs', 'data', 'config', 'user_data')"
)

if ($Checksum -ne "") {
    $Arguments += "-Checksum", "`"$Checksum`""
}

# Launch updater with elevated privileges
Write-Host "Launching updater..." -ForegroundColor Green
Write-Host "App Directory: $AppDir"
Write-Host "Executable: $ExecutableName"
Write-Host "Update Package: $UpdatePackagePath"

Start-Process PowerShell -ArgumentList $Arguments -Verb RunAs

exit 0
