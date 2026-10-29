#requires -Version 5.1
<#
DriveMate v8 diagnostics / connection setup. Does NOT launch Flutter.
-Usb: require an authorized physical phone, test backend, reverse selected serial.
-Lan: choose a physical private-network adapter with a gateway; test LAN host.
No mode / -Diagnose: read-only diagnostics. No driver/firewall/.env changes.
#>
[CmdletBinding()]
param(
    [switch]$Usb,
    [switch]$Lan,
    [switch]$Diagnose,
    [string]$DeviceId = '',
    [string]$LanIp = '',
    [string]$AdbPath = '',
    [ValidateRange(1,65535)][int]$Port = 8000
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phone_common.ps1')
$root = Split-Path -Parent $PSScriptRoot
try {
    if ($Usb -and $Lan) { Stop-DmConnection 'Choose -Usb OR -Lan, not both.' 2 }
    if ($Diagnose -or (-not $Usb -and -not $Lan)) {
        Invoke-DmDiagnostics -Root $root -AdbPath $AdbPath -Port $Port
        exit 0
    }
    $mode = if ($Lan) { 'Lan' } else { 'Usb' }
    $connection = Invoke-DmConnection -Root $root -Mode $mode -DeviceId $DeviceId -LanIp $LanIp -AdbPath $AdbPath -Port $Port
    Write-DmOk "Setup complete: $($connection.ApiBase)"
    Write-Host 'Next: use tools\run_phone.ps1 -Usb or -Lan. It stops automatically if prerequisites fail.'
    Write-DmWarn 'Old semicolon chains keep going after failed commands. Prefer the single v8 launcher.'
    exit 0
} catch {
    Write-Host "`n  [X] $($_.Exception.Message)" -ForegroundColor Red
    exit (Get-DmExitCode -ErrorRecord $_)
}
