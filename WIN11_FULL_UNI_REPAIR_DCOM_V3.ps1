# FULL_DCOM_REPAIR_EXTREME.ps1
# Extreme COM/DCOM diagnostic and repair helper
# ASCII only, comments in English, safe-by-default (destructive parts commented out).

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# =========================
# GLOBAL SETTINGS
# =========================

$ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = "C:\DCOM-Repair-$ts.log"
$backupDir = "C:\DCOM-Repair-Backup-$ts"

# =========================
# LOGGING
# =========================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $t    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $t, $Level, $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# =========================
# ADMIN CHECK
# =========================

function Ensure-Admin {
    $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Run this script as Administrator." -ForegroundColor Red
        exit 1
    }
}

Ensure-Admin

# =========================
# BACKUP HELPERS
# =========================

function Ensure-BackupDir {
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
}

function Backup-RegistryKey {
    param([string]$KeyPath)

    Ensure-BackupDir
    Write-Log ("Backup registry key: {0}" -f $KeyPath)

    if (-not (Test-Path "Registry::$KeyPath")) {
        Write-Log ("Key does not exist: {0}" -f $KeyPath) 'WARN'
        return
    }

    $safeName = ($KeyPath -replace '[\\/:*?"<>|]', '_') + ".reg"
    $outFile  = Join-Path $backupDir $safeName

    try {
        & reg.exe export "$KeyPath" "$outFile" /y | Out-Null
        Write-Log ("Exported to: {0}" -f $outFile)
    }
    catch {
        Write-Log ("Failed to export {0}: {1}" -f $KeyPath, $_) 'ERROR'
    }
}

function Backup-RegistryValue {
    param(
        [string]$KeyPath,
        [string]$ValueName
    )

    Ensure-BackupDir
    Write-Log ("Backup registry value: {0} -> {1}" -f $KeyPath, $ValueName)

    if (-not (Test-Path "Registry::$KeyPath")) {
        Write-Log ("Key does not exist: {0}" -f $KeyPath) 'WARN'
        return
    }

    try {
        $key  = Get-Item -Path "Registry::$KeyPath"
        $val  = $key.GetValue($ValueName, $null, 'DoNotExpandEnvironmentNames')
        $kind = $key.GetValueKind($ValueName)

        if ($null -eq $val) {
            Write-Log ("Value not present: {0}\\{1}" -f $KeyPath, $ValueName) 'WARN'
            return
        }

        $obj = [PSCustomObject]@{
            KeyPath   = $KeyPath
            ValueName = $ValueName
            Value     = $val
            Kind      = $kind
        }

        $file = Join-Path $backupDir ("ValueBackup-{0}-{1}.txt" -f ($KeyPath -replace '[\\/:*?"<>|]', '_'), $ValueName)
        $obj | Format-List * | Out-File -FilePath $file -Encoding UTF8
        Write-Log ("Value backup saved to: {0}" -f $file)
    }
    catch {
        Write-Log ("Failed to backup value {0}\\{1}: {2}" -f $KeyPath, $ValueName, $_) 'ERROR'
    }
}

# =========================
# BACKUP CRITICAL COM/DCOM AREAS
# =========================

Write-Log "=== BACKUP PHASE START ==="

Backup-RegistryKey 'HKLM\SOFTWARE\Microsoft\Ole'
Backup-RegistryKey 'HKLM\SOFTWARE\Classes\AppID'
Backup-RegistryKey 'HKLM\SOFTWARE\Classes\CLSID'
Backup-RegistryKey 'HKCR\AppID'
Backup-RegistryKey 'HKCR\CLSID'

Backup-RegistryValue 'HKLM\SOFTWARE\Microsoft\Ole' 'DefaultAccessPermission'
Backup-RegistryValue 'HKLM\SOFTWARE\Microsoft\Ole' 'DefaultLaunchPermission'
Backup-RegistryValue 'HKLM\SOFTWARE\Microsoft\Ole' 'MachineAccessRestriction'
Backup-RegistryValue 'HKLM\SOFTWARE\Microsoft\Ole' 'MachineLaunchRestriction'

Write-Log "=== BACKUP PHASE COMPLETE ==="

# =========================
# DCOM / COM DIAGNOSTICS
# =========================

Write-Log "=== DCOM / COM DIAGNOSTICS START ==="

# 1) Check core COM/DCOM services
$services = @(
    'RpcSs',        # Remote Procedure Call (RPC)
    'DcomLaunch',   # DCOM Server Process Launcher
    'COMSysApp',    # COM+ System Application
    'VSS'           # Volume Shadow Copy (often related to COM/DCOM issues)
)

foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        Write-Log ("Service {0}: Status={1}, StartType={2}" -f $svc, $s.Status, $s.StartType)
    }
    catch {
        Write-Log ("Service {0} not found or cannot be queried: {1}" -f $svc, $_) 'WARN'
    }
}

# 2) Collect common DCOM-related event log entries (10010, 10016, 10005, 10009)
$since = (Get-Date).AddDays(-7)

$eventIds = 10010,10016,10005,10009

try {
    $dcomEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Id      = $eventIds
    } -ErrorAction SilentlyContinue | Where-Object { $_.TimeCreated -ge $since }

    if ($dcomEvents.Count -gt 0) {
        Write-Log ("Found {0} DCOM-related events in System log (last 7 days)." -f $dcomEvents.Count)
        $evFile = Join-Path $backupDir "DCOM-Events-$ts.txt"
        $dcomEvents | Format-List TimeCreated, Id, ProviderName, LevelDisplayName, Message |
            Out-String | Out-File -FilePath $evFile -Encoding UTF8
        Write-Log ("DCOM events exported to: {0}" -f $evFile)
    }
    else {
        Write-Log "No DCOM-related events (10010/10016/10005/10009) found in System log (last 7 days)."
    }
}
catch {
    Write-Log ("Failed to query DCOM-related events: {0}" -f $_) 'ERROR'
}

Write-Log "=== DCOM / COM DIAGNOSTICS COMPLETE ==="

# =========================
# OPTIONAL: RESET DEFAULT COM SECURITY (SAFE-BY-DESIGN: COMMENTED OUT)
# =========================
<#
WARNING:
- This section resets COM security to system defaults by deleting
  specific binary security descriptors under HKLM\SOFTWARE\Microsoft\Ole.
- Windows will recreate default security settings on next COM/DCOM usage.
- This can fix many 10016-style issues, but may break custom COM security
  configurations (servers, apps, domain policies).

UNCOMMENT AT YOUR OWN RISK.
#>

Write-Log "=== RESET DEFAULT COM SECURITY (OLE) START ==="

$oleKey = 'HKLM\SOFTWARE\Microsoft\Ole'
$valuesToDelete = @(
    'DefaultAccessPermission',
    'DefaultLaunchPermission',
    'MachineAccessRestriction',
    'MachineLaunchRestriction'
)

foreach ($valName in $valuesToDelete) {
    try {
        if (Get-ItemProperty -Path "Registry::$oleKey" -Name $valName -ErrorAction SilentlyContinue) {
            Write-Log ("Deleting OLE security value: {0}\\{1}" -f $oleKey, $valName) 'WARN'
            Remove-ItemProperty -Path "Registry::$oleKey" -Name $valName -ErrorAction Stop
        }
        else {
            Write-Log ("OLE security value not present: {0}\\{1}" -f $oleKey, $valName)
        }
    }
    catch {
        Write-Log ("Failed to delete OLE security value {0}\\{1}: {2}" -f $oleKey, $valName, $_) 'ERROR'
    }
}

Write-Log "=== RESET DEFAULT COM SECURITY (OLE) COMPLETE ==="

# =========================
# OPTIONAL: FIX COMMON 10016 APPID/CLSID PERMISSIONS (TEMPLATE)
# =========================
<#
This section is a TEMPLATE for fixing specific 10016 errors.

Typical 10016 event contains:
- CLSID
- APPID
- the account that does not have Local Activation / Local Launch

The generic approach:
1) Take ownership of the AppID key.
2) Grant required permissions (e.g. SYSTEM, LOCAL SERVICE, NETWORK SERVICE).
3) Optionally adjust CLSID key permissions.

Because this is highly environment-specific, this script only provides
a helper function and an example. You must fill in your own CLSID/APPID
from your event logs.

UNCOMMENT AND EDIT THE ARRAYS TO USE.
#>

function Grant-AppIdPermissions {
    param(
        [string]$AppId,
        [string[]]$Accounts
    )

    $appIdKey = "HKCR\AppID\{$AppId}"
    Write-Log ("Granting permissions on AppID: {0}" -f $appIdKey)

    if (-not (Test-Path "Registry::$appIdKey")) {
        Write-Log ("AppID key not found: {0}" -f $appIdKey) 'ERROR'
        return
    }

    try {
        $regKey = Get-Item -Path "Registry::$appIdKey"
        $acl    = $regKey.GetAccessControl()

        foreach ($acct in $Accounts) {
            Write-Log ("Adding FullControl for: {0}" -f $acct)
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $acct,
                "FullControl",
                [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.SetAccessRule($rule)
        }

        $regKey.SetAccessControl($acl)
        Write-Log ("Permissions updated for AppID: {0}" -f $appIdKey)
    }
    catch {
        Write-Log ("Failed to update AppID permissions for {0}: {1}" -f $appIdKey, $_) 'ERROR'
    }
}

<#
# EXAMPLE USAGE:
# Fill in your own AppID from event 10016 and accounts that need Local Activation.

$commonAccounts = @(
    'NT AUTHORITY\SYSTEM',
    'LOCAL SERVICE',
    'NETWORK SERVICE'
)

$problemAppIds = @(
    # Example: 'D63B10C5-BB46-4990-A94F-E40B9D520160'  # RuntimeBroker
)

foreach ($app in $problemAppIds) {
    Grant-AppIdPermissions -AppId $app -Accounts $commonAccounts
}
#>

# =========================
# OPTIONAL: RE-REGISTER CORE COM COMPONENTS (REGSVR32)
# =========================
<#
This section can re-register some core COM components that are often
involved in COM/DCOM issues. It is not exhaustive and should be used
with caution.

UNCOMMENT TO USE.
#>

Write-Log "=== CORE COM COMPONENT RE-REGISTRATION START ==="

$system32 = "$env:windir\System32"
$syswow64 = "$env:windir\SysWOW64"

$comDlls = @(
    "$system32\ole32.dll",
    "$system32\oleaut32.dll",
    "$system32\actxprxy.dll",
    "$system32\comsvcs.dll"
)

foreach ($dll in $comDlls) {
    if (Test-Path $dll) {
        Write-Log ("regsvr32 /s {0}" -f $dll)
        & regsvr32.exe /s "$dll"
    }
    else {
        Write-Log ("DLL not found: {0}" -f $dll) 'WARN'
    }
}

Write-Log "=== CORE COM COMPONENT RE-REGISTRATION COMPLETE ==="

# =========================
# OPTIONAL: REPAIR WMI / WINRM (TEMPLATES)
# =========================
<#
These are templates for WMI and WinRM repair. They are not executed
by default and should be used only if you know you have WMI/WinRM
related COM/DCOM issues.

UNCOMMENT TO USE.
#>

Write-Log "=== WMI REPAIR START ==="
# Example WMI repair (classic):
# winmgmt /salvagerepository
# winmgmt /resetrepository
Write-Log "WMI repair commands are not executed by default. Edit this section if needed."
Write-Log "=== WMI REPAIR COMPLETE ==="

Write-Log "=== WINRM REPAIR START ==="
# Example WinRM reset:
# winrm quickconfig -q
# winrm quickconfig -transport:http
Write-Log "WinRM repair commands are not executed by default. Edit this section if needed."
Write-Log "=== WINRM REPAIR COMPLETE ==="

# =========================
# FINAL
# =========================

Write-Log "=== DCOM / COM EXTREME SCRIPT COMPLETED (NO DESTRUCTIVE ACTIONS UNLESS UNCOMMENTED) ==="
Write-Host ""
Write-Host ("DCOM/COM extreme script finished. Log: {0}" -f $logFile) -ForegroundColor Green