# Run by the CAISSE212 installer, elevated, after the files are copied.
#
# Installs the remote-support tool (rebranded RustDesk) as a Windows service so
# a technician can reach a till nobody is sitting at, and gives it a fresh
# random permanent password. The password is handed to the POS once, through
# a DPAPI-protected file in ProgramData. The POS pushes it to the back office
# and deletes the file after a 2xx. It is never written in clear and never
# logged.
#
# Every install or upgrade rotates the password; the POS pushes the new one.
param([Parameter(Mandatory = $true)][string]$SupportDir)

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:ProgramData 'caisse212\remote_access_setup.log'
function Note([string]$m) {
    try { Add-Content -LiteralPath $log -Value ("[{0:s}] {1}" -f (Get-Date), $m) } catch {}
}

try {
    $portable = Join-Path $SupportDir 'caisse212-support.exe'
    if (-not (Test-Path -LiteralPath $portable)) { Note 'no support tool shipped, skipped'; exit 0 }

    $installed = Join-Path $env:ProgramFiles 'Caisse212-Support\Caisse212-Support.exe'

    # --silent-install copies the support folder (server.json included) to
    # Program Files and registers the service. It returns before the service
    # is fully up, hence the wait.
    Start-Process -FilePath $portable -ArgumentList '--silent-install' -Wait -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path -LiteralPath $installed) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    if (-not (Test-Path -LiteralPath $installed)) { Note 'install did not complete'; exit 0 }
    # Keep server.json current on upgrades too: the installed copy reads its own.
    $cfg = Join-Path $SupportDir 'server.json'
    if (Test-Path -LiteralPath $cfg) {
        Copy-Item -LiteralPath $cfg -Destination (Split-Path $installed) -Force
    }
    Start-Sleep -Seconds 5

    # 24 characters from 18 random bytes, URL-safe so no shell quoting issue.
    $bytes = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $pw = [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'b').Replace('=', '')

    $ok = $false
    for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
        $out = (& $installed --password $pw 2>&1 | Out-String)
        if ($out -match 'Done') { $ok = $true } else { Start-Sleep -Seconds 3 }
    }
    if (-not $ok) { Note 'permanent password was not accepted'; exit 0 }

    # LocalMachine scope: the installer (admin) writes it, the POS (a cashier
    # account) must read it. The file lives seconds — until the POS pushes it.
    Add-Type -AssemblyName System.Security
    $enc = [Security.Cryptography.ProtectedData]::Protect(
        [Text.Encoding]::UTF8.GetBytes($pw), $null,
        [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $dir = Join-Path $env:ProgramData 'caisse212'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dir 'remote_access.pending'), $enc)
    $pw = $null
    Note 'service installed, password set and handed to the POS'
} catch {
    Note ("failed: " + $_.Exception.Message)
}
exit 0
