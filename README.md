Windows 11 - UNIVERSAL DCOM REPAIR TOOL V3

This PowerShell script provides deep diagnostics with standard/advanced repair capabilities for COM/DCOM, AppID/CLSID permissions, OLE security descriptors, and core COM components.

  This PowerShell script provides deep diagnostics and optional repair capabilities for COM/DCOM, AppID/CLSID permissions, OLE security descriptors, and core COM components.
  It is designed for advanced users who need to troubleshoot:

   DCOM 10016 / 10010 / 10005 / 10009 errors
   COM security corruption
   Broken AppID/CLSID permissions
   Malfunctioning COM+ components
   Explorer.exe instability caused by COM/DCOM issues
   Corrupted OLE security descriptors
   VSS/COMSysApp/RPC‑related failures

 The script is safe by default:
    👉 All destructive repair actions are commented out.
    👉 Users must manually uncomment the sections they want to execute.


    Features:

✔ Full Registry Backup

Before any repair, the script exports critical COM/DCOM registry hives:

HKLM\SOFTWARE\Microsoft\Ole
HKLM\SOFTWARE\Classes\AppID
HKLM\SOFTWARE\Classes\CLSID
HKCR\AppID
HKCR\CLSID

It also backs up individual OLE security values:

DefaultAccessPermission
DefaultLaunchPermission
MachineAccessRestriction
MachineLaunchRestriction

✔ COM/DCOM Diagnostics
The script checks:

RPC, DCOM, COMSysApp, and VSS service states
DCOM‑related event log entries (10010, 10016, 10005, 10009)
AppID/CLSID registry consistency
OLE security descriptor presence
COM/DCOM configuration health

All results are logged to a timestamped log file.

✔ Optional Repair Modules (Commented Out by Default)
Each repair block is clearly marked and documented.
Users can uncomment the sections they want to run.


    Repair Modules Explained:


🔧 1. Reset Default COM Security (OLE)
What it does when uncommented:

Deletes OLE security descriptors under HKLM\SOFTWARE\Microsoft\Ole
Forces Windows to regenerate default COM security settings
Fixes many common 10016 errors caused by corrupted binary SDs

Risks:
Removes custom COM security configurations
Should be used only when OLE security is corrupted


🔧 2. Fix AppID Permissions (10016 Repair Template)
What it does when uncommented:

Takes a list of AppIDs
Grants SYSTEM / LOCAL SERVICE / NETWORK SERVICE full control
Fixes Local Activation / Local Launch permission errors

Notes:

You must manually insert AppIDs from your own Event Viewer
This is the correct and safe method for repairing 10016 errors


🔧 3. Re‑register Core COM Components
What it does when uncommented:  
Runs silent regsvr32 on:

ole32.dll
oleaut32.dll
actxprxy.dll
comsvcs.dll

Purpose:
Repairs broken COM registrations
Fixes issues with COM+ and OLE automation


🔧 4. Optional WMI Repair (Template)
What it does when uncommented:

Provides classic WMI repository repair commands
Useful when COM/DCOM errors originate from WMI corruption


🔧 5. Optional WinRM Repair (Template)
What it does when uncommented:
Resets WinRM configuration
Fixes COM/DCOM errors related to remote management


    Usage:

Run PowerShell as Administrator
Run the script and check the generated log file for results:
   powershell
   WIN11_FULL_UNI_REPAIR_DCOM_V3.ps1
(check log file, and run another script for repair:)
   FULL_DIAG_REPAIR_DCOM.ps1

Important Notes:
The script is designed for advanced users
All destructive actions are disabled by default
Always keep backups created by the script
Use repair modules only when you understand their impact
