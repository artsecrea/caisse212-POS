<#
  pos - CAISSE212 dev/release helper. Run `pos help` for the command list.
#>
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Builder = Join-Path $Root 'build_windows.ps1'
$OutDir = Join-Path $Root 'build\release'

function Invoke-Builder([hashtable]$opts) {
    & $Builder @opts
    exit $LASTEXITCODE
}

function Get-PubspecVersion {
    $m = Select-String -Path (Join-Path $Root 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value } else { '?' }
}

$arg1 = if ($Rest) { $Rest[0] } else { $null }

switch ($Command.ToLower()) {
    'build' {
        # Current pubspec version, full pipeline.
        Invoke-Builder @{}
    }
    'release' {
        # Bumps build+1 always; patch+1 unless an explicit version is given.
        if ($arg1) { Invoke-Builder @{ Bump = $true; Version = $arg1 } }
        else { Invoke-Builder @{ Bump = $true } }
    }
    'support' {
        # Rebuild the remote-support tool (RustDesk fork) and refresh
        # C:\c212build\dist\support + dist\tech. Rarely needed - only when the
        # server/key or the fork's locked settings change. Several minutes.
        $s = 'C:\c212build\build_support.ps1'
        if (-not (Test-Path $s)) { Write-Host "[FAIL] $s not found" -ForegroundColor Red; exit 1 }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $s @Rest
        exit $LASTEXITCODE
    }
    'all' {
        # Everything end to end: rebuild the remote tool, then build the POS
        # (which embeds KDS, compiles the updater, bundles dist\support, zips,
        # and makes the installer). `pos all release` bumps the version too.
        $s = 'C:\c212build\build_support.ps1'
        if (Test-Path $s) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $s
            if ($LASTEXITCODE -ne 0) { Write-Host '[FAIL] remote-support build failed' -ForegroundColor Red; exit $LASTEXITCODE }
        } else {
            Write-Warning "No $s - skipping remote-support rebuild, using the existing dist\support"
        }
        if ($arg1 -eq 'release') { Invoke-Builder @{ Bump = $true } }
        elseif ($arg1) { Invoke-Builder @{ Bump = $true; Version = $arg1 } }
        else { Invoke-Builder @{} }
    }
    'pack' { Invoke-Builder @{ SkipBuild = $true } }
    'zip' { Invoke-Builder @{ NoInstaller = $true } }
    'setup' { Invoke-Builder @{ SkipBuild = $true; NoZip = $true } }
    'version' { Write-Host (Get-PubspecVersion) }
    'open' {
        New-Item -ItemType Directory -Force $OutDir | Out-Null
        Start-Process explorer.exe $OutDir
    }
    'run' {
        Push-Location $Root
        try { & flutter run -d windows @Rest } finally { Pop-Location }
        exit $LASTEXITCODE
    }
    'gen' {
        Push-Location $Root
        try { & dart run build_runner build --delete-conflicting-outputs } finally { Pop-Location }
        exit $LASTEXITCODE
    }
    'clean' {
        Push-Location $Root
        try { & flutter clean; & flutter pub get } finally { Pop-Location }
        exit $LASTEXITCODE
    }
    'path' {
        # Lets `pos` be typed from any folder / any shell.
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';') -contains $Root) {
            Write-Host "Already on PATH: $Root"
        } else {
            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$Root"), 'User')
            Write-Host "Added to your PATH: $Root"
            Write-Host 'Open a NEW terminal, then just type: pos help'
        }
    }
    default {
        Write-Host @"
pos - CAISSE212 builder        (current version: $(Get-PubspecVersion))

  pos build            build the current version -> zip + installer
  pos release          bump version (patch+1, build+1) -> build -> zip + installer
  pos release 1.3.0    set version 1.3.0 (build+1) -> build -> zip + installer
  pos support          rebuild the remote-support tool -> dist\support + dist\tech
  pos all              rebuild remote tool, then full POS build (zip + installer)
  pos all release      same, and bump the version first
  pos pack             no flutter build; repackage last build -> zip + installer
  pos zip              build -> zip only (no installer)
  pos setup            no flutter build; installer only
  pos version          show pubspec version
  pos open             open build\release in Explorer
  pos run [args]       flutter run -d windows
  pos gen              build_runner (drift/riverpod/json codegen)
  pos clean            flutter clean + pub get
  pos path             add this folder to your PATH so 'pos' works anywhere

Output: build\release\caisse212-<ver>+<build>-windows.zip, caisse212-setup-<ver>.exe
"@
    }
}
