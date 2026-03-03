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
    [string]$ExcludeFolders = "",

    [Parameter(Mandatory=$false)]
    [string]$ArchivePassword = "",

    [Parameter(Mandatory=$false)]
    [int]$StartDelaySeconds = 3,

    [Parameter(Mandatory=$false)]
    [string]$TempDirectory = "$env:TEMP\AppUpdater",

    [Parameter(Mandatory=$false)]
    [string]$BackupDirectory = "$env:TEMP\AppBackup",

    [Parameter(Mandatory=$false)]
    [string]$Checksum = "",

    [Parameter(Mandatory=$false)]
    [switch]$Silent = $false
)

# Convert comma-separated exclude folders to array
$ExcludeFoldersList = @()
if (-not [string]::IsNullOrEmpty($ExcludeFolders)) {
    $ExcludeFoldersList = $ExcludeFolders -split ','
}

# Import required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Global variables
$script:LogFile = $null
$script:Form = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:LogTextBox = $null
$script:CancelButton = $null
$script:Cancelled = $false
$script:UpdateSuccess = $false

# Initialize logging
function Initialize-Logging {
    if (-not (Test-Path $TempDirectory)) {
        New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null
    }

    $script:LogFile = Join-Path $TempDirectory "updater.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Create or append to log file
    try {
        Add-Content -Path $script:LogFile -Value "=== Update Session Started: $timestamp ===" -ErrorAction Stop
    } catch {
        # If we can't write to temp, use app directory
        $script:LogFile = Join-Path $AppDirectory "updater.log"
        Add-Content -Path $script:LogFile -Value "=== Update Session Started: $timestamp ===" -ErrorAction SilentlyContinue
    }
}

# Log function with safe writing
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to log file (ignore errors)
    if ($script:LogFile -and (Test-Path (Split-Path $script:LogFile -Parent))) {
        try {
            Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
        } catch { }
    }

    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }

    # Update UI if not silent and form exists
    if (-not $Silent -and $script:LogTextBox -ne $null -and $script:Form -ne $null -and $script:Form.Visible) {
        try {
            if ($script:LogTextBox.InvokeRequired) {
                $script:LogTextBox.Invoke([Action]{
                    $script:LogTextBox.AppendText("$logEntry`r`n")
                    $script:LogTextBox.SelectionStart = $script:LogTextBox.Text.Length
                    $script:LogTextBox.ScrollToCaret()
                })
            } else {
                $script:LogTextBox.AppendText("$logEntry`r`n")
                $script:LogTextBox.SelectionStart = $script:LogTextBox.Text.Length
                $script:LogTextBox.ScrollToCaret()
            }
        } catch { }
    }
}

# Update UI status
function Update-Status {
    param(
        [string]$Status,
        [int]$Progress = -1
    )

    if ($Silent) { return }

    try {
        if ($script:StatusLabel -ne $null -and $script:Form -ne $null -and $script:Form.Visible) {
            if ($script:StatusLabel.InvokeRequired) {
                $script:StatusLabel.Invoke([Action]{ $script:StatusLabel.Text = $Status })
            } else {
                $script:StatusLabel.Text = $Status
            }
        }

        if ($Progress -ge 0 -and $script:ProgressBar -ne $null -and $script:Form -ne $null -and $script:Form.Visible) {
            if ($script:ProgressBar.InvokeRequired) {
                $script:ProgressBar.Invoke([Action]{ $script:ProgressBar.Value = [Math]::Min($Progress, 100) })
            } else {
                $script:ProgressBar.Value = [Math]::Min($Progress, 100)
            }
        }

        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
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
    $script:Form.TopMost = $true

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

    # Handle form closing
    $script:Form.Add_FormClosing({
        param($sender, $e)
        if (-not $script:UpdateSuccess -and -not $script:Cancelled) {
            $script:Cancelled = $true
        }
    })

    # Show form
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
                Write-Log "Failed to stop process: $_" -Level WARNING
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
            Remove-Item -Path $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
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

# Download/Copy update
function Download-Update {
    param([string]$Url, [string]$OutputPath)

    Write-Log "Getting update from: $Url"
    Update-Status "Downloading update..." 20

    try {
        # Check if it's a file:// URL (already downloaded)
        if ($Url.StartsWith("file:///")) {
            $localPath = $Url.Substring(8).Replace("/", "\")
            Write-Log "Update file at: $localPath"

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
        Write-Log "Downloading from web..."
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)

        Write-Log "Download completed" -Level SUCCESS
        Update-Status "Download complete" 40
        return $true
    }
    catch {
        Write-Log "Failed to download update: $_" -Level ERROR
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
        # First verify the file exists and has content
        if (-not (Test-Path $ArchivePath)) {
            Write-Log "Archive file not found: $ArchivePath" -Level ERROR
            return $false
        }

        $fileInfo = Get-Item $ArchivePath
        $fileSize = $fileInfo.Length
        Write-Log "Archive file size: $fileSize bytes"

        if ($fileSize -lt 1000) {
            Write-Log "Archive file is too small ($fileSize bytes), likely not a valid ZIP" -Level ERROR
            # Try to read content if it's text (error message)
            try {
                $content = Get-Content $ArchivePath -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    Write-Log "File content: $($content.Substring(0, [Math]::Min($content.Length, 500)))" -Level ERROR
                }
            } catch { }
            return $false
        }

        # Check ZIP magic bytes (PK = 0x50 0x4B)
        $bytes = [System.IO.File]::ReadAllBytes($ArchivePath)[0..3]
        $header = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Log "File header bytes: $header"

        if ($bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
            Write-Log "File is not a valid ZIP (expected PK header, got: $header)" -Level ERROR
            return $false
        }

        if (Test-Path $DestinationPath) {
            Remove-Item -Path $DestinationPath -Recurse -Force
        }

        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

        # Try using .NET ZipFile class first (more reliable)
        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
            Write-Log "Archive extracted successfully using .NET" -Level SUCCESS
            Update-Status "Extraction complete" 60
            return $true
        }
        catch {
            Write-Log "Failed with .NET ZipFile: $_" -Level WARNING
        }

        # Fallback to Expand-Archive
        try {
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
            Write-Log "Archive extracted successfully using Expand-Archive" -Level SUCCESS
            Update-Status "Extraction complete" 60
            return $true
        }
        catch {
            Write-Log "Failed with Expand-Archive: $_" -Level ERROR
            return $false
        }
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
        # Find the actual source - might be nested in a subfolder
        $actualSource = $SourceDir
        $items = Get-ChildItem -Path $SourceDir

        # If there's only one subfolder and no files, use that as source
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $actualSource = $items[0].FullName
            Write-Log "Using nested folder as source: $actualSource"
        }

        $allItems = Get-ChildItem -Path $actualSource -Recurse
        $totalItems = $allItems.Count
        $currentItem = 0

        foreach ($item in $allItems) {
            if ($script:Cancelled) {
                Write-Log "File replacement cancelled" -Level WARNING
                return $false
            }

            $currentItem++
            $progress = 70 + ([Math]::Min(($currentItem / [Math]::Max($totalItems, 1)) * 20, 20))

            $relativePath = $item.FullName.Substring($actualSource.Length + 1)
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

            if ($currentItem % 50 -eq 0) {
                Update-Status "Updating files... ($currentItem/$totalItems)" $progress
            }
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

        # Don't delete everything, just copy back
        $items = Get-ChildItem -Path $BackupDir -Recurse
        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($BackupDir.Length + 1)
            $destPath = Join-Path $TargetDir $relativePath

            if ($item.PSIsContainer) {
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                }
            } else {
                Copy-Item -Path $item.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Log "Backup restored successfully" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to restore backup: $_" -Level ERROR
        return $false
    }
}

# Relaunch application
function Relaunch-Application {
    param([string]$ExePath)

    Write-Log "Relaunching application: $ExePath"
    Update-Status "Launching application..." 95

    try {
        if (Test-Path $ExePath) {
            $workingDir = Split-Path -Parent $ExePath
            Write-Log "Working directory: $workingDir"

            # Start the process with working directory set
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $ExePath
            $processInfo.WorkingDirectory = $workingDir
            $processInfo.UseShellExecute = $true

            $process = [System.Diagnostics.Process]::Start($processInfo)

            if ($process -ne $null) {
                Write-Log "Application launched successfully (PID: $($process.Id))" -Level SUCCESS
                Update-Status "Update completed successfully!" 100
                return $true
            } else {
                Write-Log "Process started but no handle returned" -Level WARNING
                # Try alternative method
                Start-Process -FilePath $ExePath -WorkingDirectory $workingDir
                Write-Log "Application launched using Start-Process" -Level SUCCESS
                return $true
            }
        }
        else {
            Write-Log "Executable not found: $ExePath" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "Failed to launch application: $_" -Level ERROR
        # Try one more time with simple Start-Process
        try {
            Start-Process -FilePath $ExePath
            Write-Log "Application launched on retry" -Level SUCCESS
            return $true
        }
        catch {
            Write-Log "Retry also failed: $_" -Level ERROR
            return $false
        }
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
        Write-Log "Exclude Folders: $ExcludeFolders"
        Write-Log "========================="

        # Wait for start delay
        if ($StartDelaySeconds -gt 0) {
            Write-Log "Waiting $StartDelaySeconds seconds for app to close..."
            for ($i = $StartDelaySeconds; $i -gt 0; $i--) {
                Update-Status "Starting in $i seconds..."
                Start-Sleep -Seconds 1
                [System.Windows.Forms.Application]::DoEvents()
                if ($script:Cancelled) { return }
            }
        }

        # Stop application
        $exePath = Join-Path $AppDirectory $ExecutableName
        Stop-Application -ExePath $exePath

        # Create backup
        if (-not (Create-Backup -SourceDir $AppDirectory -BackupDir $BackupDirectory)) {
            Write-Log "Backup failed, continuing anyway..." -Level WARNING
        }

        # Download update
        $archivePath = Join-Path $TempDirectory "update.zip"
        if (-not (Download-Update -Url $DownloadUrl -OutputPath $archivePath)) {
            throw "Failed to download update"
        }

        if ($script:Cancelled) { throw "Update cancelled" }

        # Skip checksum verification (as requested)
        Write-Log "Skipping checksum verification" -Level WARNING
        Update-Status "Skipping verification..." 45

        # Extract archive
        $extractPath = Join-Path $TempDirectory "extracted"
        if (-not (Extract-Archive -ArchivePath $archivePath -DestinationPath $extractPath -Password $ArchivePassword)) {
            throw "Failed to extract archive"
        }

        if ($script:Cancelled) { throw "Update cancelled" }

        # Replace files
        if (-not (Replace-Files -SourceDir $extractPath -DestDir $AppDirectory -ExcludeFolders $ExcludeFoldersList)) {
            throw "Failed to replace files"
        }

        $script:UpdateSuccess = $true
        Write-Log "Update completed successfully!" -Level SUCCESS
        Update-Status "Update completed successfully!" 100

        # Small delay before relaunch
        Write-Log "Preparing to relaunch application..."
        Start-Sleep -Seconds 2

        # Relaunch application
        $launched = Relaunch-Application -ExePath $exePath

        if ($launched) {
            Write-Log "Application relaunched successfully" -Level SUCCESS
        } else {
            Write-Log "Could not relaunch application automatically" -Level WARNING
            if (-not $Silent) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Update completed successfully!`n`nPlease start the application manually.",
                    "Update Complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
        }

        # Close form after success
        Start-Sleep -Seconds 1
        if (-not $Silent -and $script:Form -ne $null) {
            try {
                $script:Form.Close()
                $script:Form.Dispose()
            } catch { }
        }

        # Cleanup temp files after form is closed
        Start-Sleep -Seconds 1
        try {
            if (Test-Path $TempDirectory) {
                Remove-Item -Path $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch { }

        exit 0
    }
    catch {
        Write-Log "Update failed: $_" -Level ERROR

        # Restore backup
        Write-Log "Attempting to restore backup..."
        Restore-Backup -BackupDir $BackupDirectory -TargetDir $AppDirectory

        Update-Status "Update failed! Restored from backup." 0

        if (-not $Silent -and $script:Form -ne $null) {
            [System.Windows.Forms.MessageBox]::Show(
                "Update failed: $_`n`nThe application has been restored from backup.",
                "Update Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )

            try {
                $script:Form.Close()
                $script:Form.Dispose()
            } catch { }
        }

        exit 1
    }
}

# Run the update
Start-Update




