# Windows Application Updater
# Author: Auto-generated
# Description: Robust self-update system with WinForms UI

param(
    [Parameter(Mandatory=$true)]
    [string]$DownloadUrl,

    [Parameter(Mandatory=$true)]
    [string]$AppDirectory,

    [Parameter(Mandatory=$true)]
    [string]$ExecutableName,

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeFolders = @(),

    [Parameter(Mandatory=$false)]
    [string]$ArchivePassword = "",

    [Parameter(Mandatory=$false)]
    [int]$StartDelaySeconds = 5,

    [Parameter(Mandatory=$false)]
    [string]$TempDirectory = "$env:TEMP\AppUpdater",

    [Parameter(Mandatory=$false)]
    [string]$BackupDirectory = "$env:TEMP\AppBackup",

    [Parameter(Mandatory=$false)]
    [string]$Checksum = "",

    [Parameter(Mandatory=$false)]
    [switch]$Silent = $false
)

# Import required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:LogFile = Join-Path $TempDirectory "updater.log"
$script:Form = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:LogTextBox = $null
$script:CancelButton = $null
$script:Cancelled = $false

# Initialize logging
function Initialize-Logging {
    if (-not (Test-Path $TempDirectory)) {
        New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogFile -Value "=== Update Session Started: $timestamp ==="
}

# Log function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to log file
    Add-Content -Path $script:LogFile -Value $logEntry

    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }

    # Update UI if not silent
    if (-not $Silent -and $script:LogTextBox -ne $null) {
        $script:LogTextBox.Invoke([Action]{
            $script:LogTextBox.AppendText("$logEntry`r`n")
            $script:LogTextBox.SelectionStart = $script:LogTextBox.Text.Length
            $script:LogTextBox.ScrollToCaret()
        })
    }
}

# Update UI status
function Update-Status {
    param(
        [string]$Status,
        [int]$Progress = -1
    )

    if ($Silent) { return }

    if ($script:StatusLabel -ne $null) {
        $script:StatusLabel.Invoke([Action]{
            $script:StatusLabel.Text = $Status
        })
    }

    if ($Progress -ge 0 -and $script:ProgressBar -ne $null) {
        $script:ProgressBar.Invoke([Action]{
            $script:ProgressBar.Value = [Math]::Min($Progress, 100)
        })
    }
}

# Create WinForms UI
function Initialize-UI {
    if ($Silent) { return }

    # Create form
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = "Application Updater"
    $script:Form.Size = New-Object System.Drawing.Size(600, 500)
    $script:Form.StartPosition = "CenterScreen"
    $script:Form.FormBorderStyle = "FixedDialog"
    $script:Form.MaximizeBox = $false
    $script:Form.MinimizeBox = $false

    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Updating Application..."
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(560, 30)
    $titleLabel.TextAlign = "MiddleCenter"
    $script:Form.Controls.Add($titleLabel)

    # Status label
    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Text = "Initializing update..."
    $script:StatusLabel.Location = New-Object System.Drawing.Point(20, 60)
    $script:StatusLabel.Size = New-Object System.Drawing.Size(560, 20)
    $script:Form.Controls.Add($script:StatusLabel)

    # Progress bar
    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Location = New-Object System.Drawing.Point(20, 90)
    $script:ProgressBar.Size = New-Object System.Drawing.Size(560, 25)
    $script:ProgressBar.Style = "Continuous"
    $script:Form.Controls.Add($script:ProgressBar)

    # Log text box
    $script:LogTextBox = New-Object System.Windows.Forms.TextBox
    $script:LogTextBox.Location = New-Object System.Drawing.Point(20, 130)
    $script:LogTextBox.Size = New-Object System.Drawing.Size(560, 280)
    $script:LogTextBox.Multiline = $true
    $script:LogTextBox.ScrollBars = "Vertical"
    $script:LogTextBox.ReadOnly = $true
    $script:LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:Form.Controls.Add($script:LogTextBox)

    # Cancel button
    $script:CancelButton = New-Object System.Windows.Forms.Button
    $script:CancelButton.Text = "Cancel"
    $script:CancelButton.Location = New-Object System.Drawing.Point(250, 420)
    $script:CancelButton.Size = New-Object System.Drawing.Size(100, 30)
    $script:CancelButton.Add_Click({
        $script:Cancelled = $true
        $script:CancelButton.Enabled = $false
        Write-Log "Update cancelled by user" -Level WARNING
    })
    $script:Form.Controls.Add($script:CancelButton)

    # Show form asynchronously
    $script:Form.Show()
    [System.Windows.Forms.Application]::DoEvents()
}

# Stop running application
function Stop-Application {
    param([string]$ExePath)

    Write-Log "Attempting to stop application: $ExePath"
    Update-Status "Stopping application..." 5

    $processName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue

    if ($processes) {
        Write-Log "Found $($processes.Count) running instance(s)"

        foreach ($process in $processes) {
            try {
                $process.CloseMainWindow() | Out-Null
                Start-Sleep -Seconds 2

                if (-not $process.HasExited) {
                    Write-Log "Force killing process $($process.Id)"
                    $process.Kill()
                }

                $process.WaitForExit(5000)
                Write-Log "Process stopped successfully" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to stop process: $_" -Level ERROR
                return $false
            }
        }
    }
    else {
        Write-Log "No running instances found"
    }

    return $true
}

# Create backup
function Create-Backup {
    param([string]$SourceDir, [string]$BackupDir)

    Write-Log "Creating backup of $SourceDir"
    Update-Status "Creating backup..." 10

    try {
        if (Test-Path $BackupDir) {
            Write-Log "Removing old backup"
            Remove-Item -Path $BackupDir -Recurse -Force
        }

        Write-Log "Copying files to $BackupDir"
        Copy-Item -Path $SourceDir -Destination $BackupDir -Recurse -Force
        Write-Log "Backup created successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to create backup: $_" -Level ERROR
        return $false
    }
}

# Download update
function Download-Update {
    param([string]$Url, [string]$OutputPath)

    Write-Log "Downloading update from: $Url"
    Update-Status "Downloading update..." 20

    try {
        # Check if it's a file:// URL (already downloaded)
        if ($Url.StartsWith("file:///")) {
            $localPath = $Url.Substring(8).Replace("/", "\")
            Write-Log "Update already downloaded at: $localPath"

            if (Test-Path $localPath) {
                Copy-Item -Path $localPath -Destination $OutputPath -Force
                Write-Log "Update copied successfully" -Level SUCCESS
                Update-Status "Download complete" 40
                return $true
            }
            else {
                Write-Log "Local file not found: $localPath" -Level ERROR
                return $false
            }
        }

        # Download from URL
        $webClient = New-Object System.Net.WebClient

        # Progress handler
        $webClient.DownloadProgressChanged = {
            param($sender, $e)
            $percent = [Math]::Min(20 + ($e.ProgressPercentage * 0.2), 40)
            Update-Status "Downloading... $($e.ProgressPercentage)%" $percent
        }

        # Download file
        $webClient.DownloadFileAsync($Url, $OutputPath)

        # Wait for download
        while ($webClient.IsBusy) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.Application]::DoEvents()

            if ($script:Cancelled) {
                $webClient.CancelAsync()
                return $false
            }
        }

        Write-Log "Download completed" -Level SUCCESS
        Update-Status "Download complete" 40
        return $true
    }
    catch {
        Write-Log "Failed to download update: $_" -Level ERROR
        return $false
    }
}

# Verify checksum
function Verify-Checksum {
    param([string]$FilePath, [string]$ExpectedChecksum)

    if ([string]::IsNullOrEmpty($ExpectedChecksum)) {
        Write-Log "No checksum provided, skipping verification" -Level WARNING
        return $true
    }

    Write-Log "Verifying checksum..."
    Update-Status "Verifying integrity..." 45

    try {
        $fileHash = Get-FileHash -Path $FilePath -Algorithm SHA256
        $actualChecksum = $fileHash.Hash

        if ($actualChecksum -eq $ExpectedChecksum) {
            Write-Log "Checksum verified successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Checksum mismatch! Expected: $ExpectedChecksum, Actual: $actualChecksum" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to verify checksum: $_" -Level ERROR
        return $false
    }
}

# Extract archive
function Extract-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath,
        [string]$Password
    )

    Write-Log "Extracting archive to: $DestinationPath"
    Update-Status "Extracting update..." 50

    try {
        if (Test-Path $DestinationPath) {
            Remove-Item -Path $DestinationPath -Recurse -Force
        }

        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

        # Extract using .NET or 7-Zip if available
        if ([string]::IsNullOrEmpty($Password)) {
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
        }
        else {
            # For password-protected archives, we'd need 7-Zip or similar
            # This is a placeholder - implement 7-Zip call if needed
            Write-Log "Password-protected archives require 7-Zip" -Level WARNING
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
        }

        Write-Log "Archive extracted successfully" -Level SUCCESS
        Update-Status "Extraction complete" 60
        return $true
    }
    catch {
        Write-Log "Failed to extract archive: $_" -Level ERROR
        return $false
    }
}

# Replace application files
function Replace-Files {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string[]]$ExcludeFolders
    )

    Write-Log "Replacing application files"
    Update-Status "Updating files..." 70

    try {
        $items = Get-ChildItem -Path $SourceDir -Recurse
        $totalItems = $items.Count
        $currentItem = 0

        foreach ($item in $items) {
            if ($script:Cancelled) {
                Write-Log "File replacement cancelled" -Level WARNING
                return $false
            }

            $currentItem++
            $progress = 70 + ([Math]::Min(($currentItem / $totalItems) * 20, 20))

            $relativePath = $item.FullName.Substring($SourceDir.Length + 1)
            $destPath = Join-Path $DestDir $relativePath

            # Check if in excluded folder
            $excluded = $false
            foreach ($excludeFolder in $ExcludeFolders) {
                if ($relativePath.StartsWith($excludeFolder)) {
                    $excluded = $true
                    break
                }
            }

            if ($excluded) {
                Write-Log "Skipping excluded: $relativePath"
                continue
            }

            # Copy item
            if ($item.PSIsContainer) {
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                }
            }
            else {
                $destFolder = Split-Path -Parent $destPath
                if (-not (Test-Path $destFolder)) {
                    New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
                }

                Copy-Item -Path $item.FullName -Destination $destPath -Force
            }

            Update-Status "Updating files... ($currentItem/$totalItems)" $progress
        }

        Write-Log "Files replaced successfully" -Level SUCCESS
        Update-Status "Update complete" 90
        return $true
    }
    catch {
        Write-Log "Failed to replace files: $_" -Level ERROR
        return $false
    }
}

# Restore backup
function Restore-Backup {
    param([string]$BackupDir, [string]$TargetDir)

    Write-Log "Restoring backup from: $BackupDir"
    Update-Status "Restoring backup..."

    try {
        if (-not (Test-Path $BackupDir)) {
            Write-Log "Backup not found!" -Level ERROR
            return $false
        }

        Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $BackupDir -Destination $TargetDir -Recurse -Force

        Write-Log "Backup restored successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to restore backup: $_" -Level ERROR
        return $false
    }
}

# Cleanup temporary files
function Cleanup-TempFiles {
    Write-Log "Cleaning up temporary files"

    try {
        if (Test-Path $TempDirectory) {
            Remove-Item -Path $TempDirectory -Recurse -Force
        }
        Write-Log "Cleanup complete" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to cleanup: $_" -Level WARNING
    }
}

# Relaunch application
function Relaunch-Application {
    param([string]$ExePath)

    Write-Log "Relaunching application: $ExePath"
    Update-Status "Launching application..." 95

    try {
        if (Test-Path $ExePath) {
            Start-Process -FilePath $ExePath
            Write-Log "Application launched successfully" -Level SUCCESS
            Update-Status "Update completed successfully!" 100
            return $true
        }
        else {
            Write-Log "Executable not found: $ExePath" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to launch application: $_" -Level ERROR
        return $false
    }
}

# Main update process
function Start-Update {
    try {
        Initialize-Logging
        Initialize-UI

        Write-Log "=== Update Parameters ==="
        Write-Log "Download URL: $DownloadUrl"
        Write-Log "App Directory: $AppDirectory"
        Write-Log "Executable: $ExecutableName"
        Write-Log "Exclude Folders: $($ExcludeFolders -join ', ')"
        Write-Log "========================="

        # Wait for start delay
        if ($StartDelaySeconds -gt 0) {
            Write-Log "Waiting $StartDelaySeconds seconds before starting..."
            for ($i = $StartDelaySeconds; $i -gt 0; $i--) {
                Update-Status "Starting in $i seconds..."
                Start-Sleep -Seconds 1
                if ($script:Cancelled) { return }
            }
        }

        # Stop application
        $exePath = Join-Path $AppDirectory $ExecutableName
        if (-not (Stop-Application -ExePath $exePath)) {
            throw "Failed to stop application"
        }

        # Create backup
        if (-not (Create-Backup -SourceDir $AppDirectory -BackupDir $BackupDirectory)) {
            throw "Failed to create backup"
        }

        # Download update
        $archivePath = Join-Path $TempDirectory "update.zip"
        if (-not (Download-Update -Url $DownloadUrl -OutputPath $archivePath)) {
            throw "Failed to download update"
        }

        if ($script:Cancelled) { throw "Update cancelled" }

        # Verify checksum
        if (-not (Verify-Checksum -FilePath $archivePath -ExpectedChecksum $Checksum)) {
            throw "Checksum verification failed"
        }

        # Extract archive
        $extractPath = Join-Path $TempDirectory "extracted"
        if (-not (Extract-Archive -ArchivePath $archivePath -DestinationPath $extractPath -Password $ArchivePassword)) {
            throw "Failed to extract archive"
        }

        if ($script:Cancelled) { throw "Update cancelled" }

        # Replace files
        if (-not (Replace-Files -SourceDir $extractPath -DestDir $AppDirectory -ExcludeFolders $ExcludeFolders)) {
            throw "Failed to replace files"
        }

        # Cleanup temp files
        Cleanup-TempFiles

        # Relaunch application
        Start-Sleep -Seconds 2
        Relaunch-Application -ExePath $exePath

        # Close updater
        Start-Sleep -Seconds 3
        if (-not $Silent -and $script:Form -ne $null) {
            $script:Form.Close()
        }

        Write-Log "Update completed successfully!" -Level SUCCESS
        exit 0
    }
    catch {
        Write-Log "Update failed: $_" -Level ERROR

        # Restore backup
        Write-Log "Attempting to restore backup..."
        Restore-Backup -BackupDir $BackupDirectory -TargetDir $AppDirectory

        if (-not $Silent) {
            [System.Windows.Forms.MessageBox]::Show(
                "Update failed: $_`n`nThe application has been restored from backup.",
                "Update Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }

        exit 1
    }
}

# Run the update
Start-Update

# Keep form open if not silent
if (-not $Silent -and $script:Form -ne $null) {
    [System.Windows.Forms.Application]::Run($script:Form)
}
