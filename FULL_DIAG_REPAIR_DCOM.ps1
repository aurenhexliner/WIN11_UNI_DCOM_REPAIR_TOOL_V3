# FULL_DIAG_REPAIR_DCOM.ps1
# Save as UTF-8 WITH BOM

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# === GLOBAL ===
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = "C:\Explorer-Fix-$ts.log"
$backupRoot = "C:\Explorer-Fix-Backup-$ts"

# === LOGGING ===
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $t, $Level, $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# === ADMIN CHECK ===
function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Run this script as Administrator." -ForegroundColor Red
        exit 1
    }
}
Ensure-Admin

# === BACKUP FUNCTION ===
function Backup-Key {
    param([string]$KeyPath)

    Write-Log ("Backup: {0}" -f $KeyPath)

    if (-not (Test-Path "Registry::$KeyPath")) {
        Write-Log ("Key does not exist: {0}" -f $KeyPath) 'WARN'
        return
    }

    if (-not (Test-Path $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $safe = ($KeyPath -replace '[\\/:*?"<>|]', '_') + ".reg"
    $out  = Join-Path $backupRoot $safe

    try {
        & reg.exe export "$KeyPath" "$out" /y | Out-Null
    }
    catch {
        Write-Log ("Backup failed for {0}: {1}" -f $KeyPath, $_) 'ERROR'
    }
}

# === BACKUP VALID KEYS (NO WILDCARDS) ===
Backup-Key 'HKCR\Directory\shellex\ContextMenuHandlers'
Backup-Key 'HKCR\Drive\shellex\ContextMenuHandlers'
Backup-Key 'HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers'
Backup-Key 'HKCR\CLSID'

# === ENSURE HKCR PSDrive ===
if (-not (Get-PSDrive HKCR -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
}

# === SCAN EXPLORER EVENTS ===
function Scan-ExplorerEvents {
    Write-Log "Scanning Explorer.exe crashes and hangs..."

    $since = (Get-Date).AddDays(-7)

    # Crashes
    $crashFilter = @{
        LogName='Application'
        ProviderName='Application Error'
        Id=1000
    }

    $crashes = Get-WinEvent -FilterHashtable $crashFilter -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $since -and $_.Message -like '*explorer.exe*' }

    if ($crashes.Count -gt 0) {
        Write-Log ("Found {0} crash events." -f $crashes.Count)
    } else {
        Write-Log "No crash events found."
    }

    # Hangs
    $hangFilter = @{
        LogName='Application'
        ProviderName='Application Hang'
        Id=1002
    }

    $hangs = Get-WinEvent -FilterHashtable $hangFilter -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $since -and $_.Message -like '*explorer.exe*' }

    if ($hangs.Count -gt 0) {
        Write-Log ("Found {0} hang events." -f $hangs.Count)
    } else {
        Write-Log "No hang events found."
    }
}
Scan-ExplorerEvents

# === SCAN BROKEN CLSID ===
function Scan-BrokenCLSID {
    Write-Log "Scanning CLSID..."

    $broken = @()

    Get-ChildItem HKCR:\CLSID | ForEach-Object {
        $clsidKey = $_
        $val = (Get-ItemProperty -Path $clsidKey.PSPath -ErrorAction SilentlyContinue).'(default)'

        if ([string]::IsNullOrWhiteSpace($val)) {
            $broken += $clsidKey.Name
            return
        }

        if ($val -match '^[A-Za-z]:\\') {
            if (-not (Test-Path $val)) {
                $broken += $clsidKey.Name
            }
        }
    }

    Write-Log ("Broken CLSID count: {0}" -f $broken.Count)

    if ($broken.Count -gt 0) {
        $file = Join-Path $backupRoot "Broken-CLSID-$ts.txt"
        $broken | Out-File -FilePath $file -Encoding UTF8
        Write-Log ("Saved to: {0}" -f $file)
    }
}
Scan-BrokenCLSID

# === CLEAN CONTEXT MENU HANDLERS ===
function Clean-Handlers {
    param([string]$RootPath)

    Write-Log ("Cleaning handlers in {0}" -f $RootPath)

    try {
        $key = Get-Item -Path "Registry::$RootPath" -ErrorAction Stop
    }
    catch {
        Write-Log ("Cannot read {0}: {1}" -f $RootPath, $_) 'ERROR'
        return
    }

    foreach ($sub in $key.GetSubKeyNames()) {
        $subPath = "Registry::$RootPath\$sub"
        $val = (Get-ItemProperty -Path $subPath -ErrorAction SilentlyContinue).'(default)'

        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Log ("Removing empty handler: {0}" -f $subPath) 'WARN'
            Remove-Item -Path $subPath -Recurse -Force
        }
        elseif ($val -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') {
            Write-Log ("Invalid handler value: {0} = {1}" -f $subPath, $val) 'WARN'
        }
    }
}

Clean-Handlers 'HKCR\Directory\shellex\ContextMenuHandlers'
Clean-Handlers 'HKCR\Drive\shellex\ContextMenuHandlers'
Clean-Handlers 'HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers'

# === SCAN THUMBNAIL/PREVIEW HANDLERS ===
function Scan-ThumbnailPreview {
    Write-Log "Scanning Thumbnail/Preview handlers..."

    $paths = @(
        'HKCR\Directory\shellex',
        'HKCR\Drive\shellex',
        'HKCR\AllFilesystemObjects\shellex'
    )

    $found = @()

    foreach ($p in $paths) {
        try {
            $key = Get-Item -Path "Registry::$p" -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($sub in $key.GetSubKeyNames()) {
            $subPath = "Registry::$p\$sub"
            $val = (Get-ItemProperty -Path $subPath -ErrorAction SilentlyContinue).'(default)'

            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $found += "$p -> $sub = $val"
            }
        }
    }

    if ($found.Count -gt 0) {
        $file = Join-Path $backupRoot "Thumbnail-Preview-$ts.txt"
        $found | Out-File -FilePath $file -Encoding UTF8
        Write-Log ("Saved to: {0}" -f $file)
    }
    else {
        Write-Log "No Thumbnail/Preview handlers found."
    }
}
Scan-ThumbnailPreview

# === RESTART EXPLORER ===
function Restart-Explorer {
    Write-Log "Restarting Explorer.exe..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Log "Explorer.exe restarted."
}
Restart-Explorer

Write-Log "=== Repair Completed ==="

Write-Host ""
Write-Host ("Repair completed. Log: {0}" -f $logFile) -ForegroundColor Green
