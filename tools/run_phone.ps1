#requires -Version 5.1
<#
DriveMate v8 safe launcher. Default: USB. No Flutter command runs before the
selected phone/backend checks pass. -Lan -BuildApk builds for manual installation
without requiring a connected device. It still needs a reachable LAN backend.
#>
[CmdletBinding()]
param(
    [switch]$Usb,
    [switch]$Lan,
    [switch]$BuildApk,
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
    $mode = if ($Lan) { 'Lan' } else { 'Usb' }
    Invoke-DmPhoneLaunch -Root $root -Mode $mode -DeviceId $DeviceId -LanIp $LanIp -AdbPath $AdbPath -Port $Port -BuildApk:$BuildApk
    exit 0
} catch {
    Write-Host "`n  [X] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Stopped here. Do not delete the database or reinstall the backend to fix a missing ADB device.'
    exit (Get-DmExitCode -ErrorRecord $_)
}
