# DriveMate v8 connection helpers. Windows PowerShell 5.1 compatible.
# Dot-sourcing this file defines functions only. No driver, firewall or .env edit.

function Stop-DmConnection {
    param([string]$Message, [int]$Code = 1)
    $errorObject = New-Object System.InvalidOperationException -ArgumentList $Message
    $errorObject.Data['DriveMateExitCode'] = $Code
    throw $errorObject
}

function Get-DmExitCode {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception.Data.Contains('DriveMateExitCode')) { return [int]$exception.Data['DriveMateExitCode'] }
        $exception = $exception.InnerException
    }
    return 1
}

function Write-DmStep { param([string]$Text) Write-Host "`n=== $Text" -ForegroundColor Cyan }
function Write-DmOk { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-DmWarn { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }

function ConvertFrom-DmAdbDevices {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        $text = $line.Trim()
        if ($text -match '^(\S+)\s+(device|unauthorized|offline|recovery|sideload|bootloader)\b(.*)$') {
            $serial = $Matches[1]
            $state = $Matches[2]
            $details = $Matches[3].Trim()
            [pscustomobject]@{ Serial = $serial; State = $state; Details = $details; IsEmulator = ($serial -match '^emulator-\d+$' -or $details -match 'model:(sdk_|Android_SDK|Android_Emulator)') }
        } elseif ($text -match '^(\S+)\s+no permissions\b') {
            [pscustomobject]@{ Serial = $Matches[1]; State = 'no_permissions'; Details = ''; IsEmulator = $false }
        }
    }
}

function Show-DmUsbHelp {
    param([string]$State = 'missing')
    if ($State -eq 'unauthorized') {
        Write-Host 'Phone mila, lekin authorization pending hai. Unlock it and accept Allow USB debugging.' -ForegroundColor Yellow
        Write-Host 'If the popup is missing: reconnect; then try Revoke USB debugging authorizations on the phone and reconnect.'
    } elseif ($State -eq 'offline') {
        Write-Host 'Phone is listed as offline. Unlock/reconnect it and try another direct USB port.' -ForegroundColor Yellow
    } else {
        Write-Host 'ADB list is empty / no usable physical Android phone. This is not a Django server error.' -ForegroundColor Yellow
        Write-Host '1. Unlock phone -> Developer options -> USB debugging ON.'
        Write-Host '2. Try a known DATA cable, not a charge-only cable; use a direct USB port, not a hub.'
        Write-Host '3. Try File transfer (MTP) mode to check whether the data connection works.'
        Write-Host '4. Accept the Allow USB debugging popup if it appears.'
        Write-Host '5. In Windows Device Manager, check Android/ADB/Unknown devices. Use the official OEM ADB driver for your phone.'
        Write-Host 'No ZIP or adb reverse command can repair a missing data cable / Windows USB driver.'
    }
    Write-Host 'Do not reinstall Python/Django, delete your database, disable antivirus or install random driver packs.'
}

function Find-DmAdb {
    param([string]$AdbPath = '')
    if ($AdbPath) {
        if (Test-Path -LiteralPath $AdbPath -PathType Leaf) { return (Resolve-Path -LiteralPath $AdbPath).ProviderPath }
        Stop-DmConnection "ADB path does not exist: $AdbPath" 10
    }
    $candidates = @()
    foreach ($sdk in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)) {
        if ($sdk) { $candidates += Join-Path $sdk 'platform-tools\adb.exe' }
    }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' }
    if ($env:USERPROFILE) { $candidates += Join-Path $env:USERPROFILE 'Android\Sdk\platform-tools\adb.exe' }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $command = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    Stop-DmConnection 'ADB not found. Install Android SDK Platform-Tools in Android Studio, or pass -AdbPath to your existing adb.exe.' 10
}

function Invoke-DmNative {
    param([string]$Command, [string[]]$Arguments)
    # ADB prints normal daemon startup messages on stderr. Do not mistake those
    # messages for a failed command; use the native EXIT CODE.
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Command @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    [pscustomobject]@{ ExitCode = [int]$code; Lines = $lines }
}

function Invoke-DmAdb { param([string]$Adb, [string[]]$Arguments) Invoke-DmNative -Command $Adb -Arguments $Arguments }

function Get-DmDevices {
    param([string]$Adb)
    $result = Invoke-DmAdb -Adb $Adb -Arguments @('devices', '-l')
    foreach ($line in $result.Lines) { Write-Host "  $line" }
    if ($result.ExitCode -ne 0) { Stop-DmConnection 'adb devices failed. Check the ADB executable/SDK installation.' 11 }
    @(ConvertFrom-DmAdbDevices -Lines $result.Lines)
}

function Select-DmDevice {
    param([object[]]$Devices, [string]$DeviceId = '')
    $physical = @($Devices | Where-Object { -not $_.IsEmulator })
    if ($DeviceId) {
        $matching = @($physical | Where-Object { $_.Serial -eq $DeviceId })
        if ($matching.Count -ne 1) { Stop-DmConnection 'The requested device ID is not in the physical-phone ADB list. Copy an actual serial from adb devices -l.' 12 }
        $chosen = $matching[0]
        if ($chosen.State -ne 'device') { Show-DmUsbHelp -State $chosen.State; Stop-DmConnection "Selected phone is $($chosen.State), not ready." 13 }
        return $chosen
    }
    $ready = @($physical | Where-Object { $_.State -eq 'device' })
    if ($ready.Count -gt 1) { Stop-DmConnection 'More than one phone is ready. Re-run with -DeviceId and one actual serial from the list above.' 14 }
    if ($ready.Count -eq 1) { return $ready[0] }
    $bad = $physical | Select-Object -First 1
    if ($bad) { Show-DmUsbHelp -State $bad.State } else { Show-DmUsbHelp }
    Stop-DmConnection 'No authorized physical Android phone. Stopping before adb reverse / Flutter.' 15
}

function Test-DmPrivateIPv4 {
    param([string]$Address)
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return ($bytes[0] -eq 10 -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31))
}

function Get-DmNetworkConfigurations {
    if (-not (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        Stop-DmConnection 'Windows network discovery is unavailable. Run this helper in Windows PowerShell on the development PC.' 20
    }
    @(Get-NetIPConfiguration -Detailed -ErrorAction Stop)
}

function Get-DmLanCandidates {
    param([object[]]$Configurations)
    foreach ($configuration in $Configurations) {
        $adapter = $configuration.NetAdapter
        if (-not $adapter -or $adapter.Status -ne 'Up') { continue }
        # Physical adapter + default gateway. Never choose an IP just because
        # it begins with 192.168 (VirtualBox host-only commonly does too).
        if ($adapter.HardwareInterface -ne $true) { continue }
        if ($adapter.InterfaceDescription -match 'VirtualBox|VMware|Hyper-V|vEthernet|WSL|Docker|Loopback|TAP-|TUN |VPN') { continue }
        $gateway = @($configuration.IPv4DefaultGateway | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })
        if ($gateway.Count -eq 0) { continue }
        foreach ($entry in @($configuration.IPv4Address)) {
            if (Test-DmPrivateIPv4 -Address $entry.IPAddress) {
                [pscustomobject]@{ Address = $entry.IPAddress; Interface = $configuration.InterfaceAlias; Gateway = $gateway[0].NextHop }
            }
        }
    }
}

function Select-DmLanAddress {
    param([object[]]$Candidates, [string]$LanIp = '')
    $unique = @($Candidates | Sort-Object Address -Unique)
    foreach ($candidate in $unique) { Write-Host "  $($candidate.Interface): $($candidate.Address) (gateway $($candidate.Gateway))" }
    if ($LanIp) {
        $match = @($unique | Where-Object { $_.Address -eq $LanIp })
        if ($match.Count -ne 1) { Stop-DmConnection 'That -LanIp is not on an UP physical private-network adapter with a default gateway. Do not use a virtual/VPN/host-only address.' 21 }
        return $match[0].Address
    }
    if ($unique.Count -eq 1) { return $unique[0].Address }
    if ($unique.Count -gt 1) { Stop-DmConnection 'Multiple physical LAN addresses found. Choose the network shared with the phone and pass -LanIp explicitly.' 22 }
    Stop-DmConnection 'No suitable physical private LAN address with a gateway was found. Check Wi-Fi/Ethernet or use USB.' 23
}

function Get-DmConfigUrl {
    param([string]$Root)
    $path = Join-Path $Root 'frontend\lib\config.dart'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-DmConnection 'frontend/lib/config.dart not found. Keep tools beside frontend and backend.' 30 }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -match "const String apiDefaultBaseUrl = '([^']+)'") { return $Matches[1] }
    if ($text -match "const String apiBaseUrl = '([^']+)'") { return $Matches[1] }
    Stop-DmConnection 'Could not read the configured API base. Use the supplied v8 config.dart.' 30
}

function Set-DmConfigUrl {
    param([string]$Root, [string]$ApiBase)
    $uri = $null
    if (-not [Uri]::TryCreate($ApiBase, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or $uri.AbsolutePath -ne '/api' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        Stop-DmConnection 'Invalid API base; refusing to write config.dart.' 31
    }
    $path = Join-Path $Root 'frontend\lib\config.dart'
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $pattern = "const String apiDefaultBaseUrl = '[^']+'"
    $replacement = "const String apiDefaultBaseUrl = '$ApiBase'"
    if ($text -notmatch $pattern) { $pattern = "const String apiBaseUrl = '[^']+'"; $replacement = "const String apiBaseUrl = '$ApiBase'" }
    if ($text -notmatch $pattern) { Stop-DmConnection 'API constant not found; source was not changed.' 30 }
    $updated = [regex]::Replace($text, $pattern, $replacement)
    # Explicit UTF-8 without BOM; Windows PowerShell's default encoding differs
    # from modern PowerShell and must not corrupt Dart comments/fonts/strings.
    [IO.File]::WriteAllText($path, $updated, (New-Object Text.UTF8Encoding -ArgumentList $false))
    Write-DmOk "Source API default set: $ApiBase"
}

function ConvertFrom-DmHealth {
    param([int]$StatusCode, [string]$Content)
    $valid = $false
    $version = 0
    try {
        $body = $Content | ConvertFrom-Json -ErrorAction Stop
        $valid = ($StatusCode -eq 200 -and $body.status -eq 'ok' -and $body.service -eq 'drivemate-api')
        if ($body.api_version) { $version = [int]$body.api_version }
    } catch { $valid = $false }
    [pscustomobject]@{ Ok = $valid; StatusCode = $StatusCode; ApiVersion = $version }
}

function Test-DmBackend {
    param([string]$ApiBase)
    try {
        $reply = Invoke-WebRequest -Uri "$ApiBase/health/" -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -Headers @{ Accept = 'application/json' } -ErrorAction Stop
        ConvertFrom-DmHealth -StatusCode ([int]$reply.StatusCode) -Content $reply.Content
    } catch {
        $code = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $code = [int]$_.Exception.Response.StatusCode }
        [pscustomobject]@{ Ok = $false; StatusCode = $code }
    }
}

function Assert-DmBackend {
    param([string]$ApiBase)
    $health = Test-DmBackend -ApiBase $ApiBase
    $serverPort = ([Uri]$ApiBase).Port
    if (-not $health.Ok) {
        if ($health.StatusCode -eq 400) {
            Stop-DmConnection "HTTP 400 at $ApiBase/health/. Add this exact host to backend/.env ALLOWED_HOSTS and restart Django. Do not use ALLOWED_HOSTS=*." 40
        }
        if ($health.StatusCode -eq 200) { Stop-DmConnection 'HTTP 200 was returned by a different/invalid service, not DriveMate. Source was not changed.' 41 }
        Stop-DmConnection "DriveMate health failed at $ApiBase/health/ (HTTP $($health.StatusCode)). Start Django on 0.0.0.0:$serverPort; for LAN also check ALLOWED_HOSTS. No Flutter command will run." 42
    }
    if ($health.ApiVersion -lt 10) { Stop-DmConnection 'This V9.1 payment update needs backend API 10. Restart it with tools\run_backend.ps1 (install requirements + migrate) before running the phone app.' 43 }
    Write-DmOk "DriveMate health answered: $ApiBase/health/ (reachability only, not database/migration verification)"
}

function Invoke-DmConnection {
    param([string]$Root, [ValidateSet('Usb','Lan')][string]$Mode, [string]$DeviceId = '', [string]$LanIp = '',
          [string]$AdbPath = '', [int]$Port = 8000, [switch]$RequireDevice)
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'frontend') -PathType Container)) { Stop-DmConnection 'Project frontend folder not found.' 30 }
    $adb = $null
    $device = $null
    if ($Mode -eq 'Usb' -or $RequireDevice) {
        Write-DmStep 'ADB phone detection (must pass before deployment)'
        $adb = Find-DmAdb -AdbPath $AdbPath
        Write-Host "  ADB: $adb"
        $device = Select-DmDevice -Devices @(Get-DmDevices -Adb $adb) -DeviceId $DeviceId
        Write-DmOk "Authorized physical phone: $($device.Serial)"
    }
    Write-DmStep 'Backend health'
    Assert-DmBackend -ApiBase "http://127.0.0.1:$Port/api"
    if ($Mode -eq 'Usb') {
        $api = "http://127.0.0.1:$Port/api"
        Write-DmStep 'Per-device USB reverse tunnel'
        $mapping = "tcp:$Port"
        $reverse = Invoke-DmAdb -Adb $adb -Arguments @('-s', $device.Serial, 'reverse', $mapping, $mapping)
        if ($reverse.ExitCode -ne 0) { Stop-DmConnection 'adb reverse failed for the selected phone. No Flutter command will run.' 50 }
        $listed = Invoke-DmAdb -Adb $adb -Arguments @('-s', $device.Serial, 'reverse', '--list')
        $joined = $listed.Lines -join "`n"
        if ($listed.ExitCode -ne 0 -or $joined -notmatch "(?m)(^|\s)tcp:$Port\s+tcp:$Port(\s|$)") { Stop-DmConnection 'The expected reverse mapping was not confirmed. Reconnect/re-authorize the phone.' 51 }
        Write-DmOk "Tunnel confirmed for $($device.Serial): phone $Port -> PC $Port"
    } else {
        Write-DmStep 'Physical LAN interface selection'
        $ip = Select-DmLanAddress -Candidates @(Get-DmLanCandidates -Configurations @(Get-DmNetworkConfigurations)) -LanIp $LanIp
        $api = "http://${ip}:$Port/api"
        Assert-DmBackend -ApiBase $api
        Write-DmWarn "On the PHONE browser open $api/health/. PC success alone does not prove the phone/firewall path."
        Write-DmWarn 'Phone and PC must share the same LAN; campus/guest Wi-Fi can isolate clients.'
    }
    Set-DmConfigUrl -Root $Root -ApiBase $api
    Write-DmWarn 'If the app already has a custom server pin, change/reset it in Login or Account > Server connection; runtime pins override build defaults.'
    [pscustomobject]@{ ApiBase = $api; DeviceId = $(if ($device) { $device.Serial } else { '' }); Mode = $Mode }
}

function Find-DmFlutter {
    $command = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Stop-DmConnection 'flutter is not on PATH. Add the Flutter SDK bin folder, then open a new terminal.' 60 }
    $command.Source
}

function Invoke-DmFlutter {
    param([string]$Flutter, [string[]]$Arguments)
    # Stream compiler/run output LIVE (flutter run can keep this terminal open).
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Flutter @Arguments; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPreference }
    if ($code -ne 0) { Stop-DmConnection "Flutter stopped (exit $code). Read the output above; no later build/run command was started." 61 }
}

function Invoke-DmPhoneLaunch {
    param([string]$Root, [ValidateSet('Usb','Lan')][string]$Mode = 'Usb', [string]$DeviceId = '',
          [string]$LanIp = '', [string]$AdbPath = '', [int]$Port = 8000, [switch]$BuildApk)
    if ($BuildApk -and $Mode -ne 'Lan') { Stop-DmConnection 'APK without a connected phone requires -Lan -BuildApk, not a nonexistent USB tunnel.' 62 }
    $connection = Invoke-DmConnection -Root $Root -Mode $Mode -DeviceId $DeviceId -LanIp $LanIp -AdbPath $AdbPath -Port $Port -RequireDevice:(-not $BuildApk)
    $flutter = Find-DmFlutter
    Push-Location (Join-Path $Root 'frontend')
    try {
        Write-DmStep 'Flutter dependencies'
        Invoke-DmFlutter -Flutter $flutter -Arguments @('pub', 'get')
        $define = "--dart-define=API_BASE_URL=$($connection.ApiBase)"
        if ($BuildApk) {
            Write-DmStep 'Build APK (does not need ADB / a connected phone)'
            Invoke-DmFlutter -Flutter $flutter -Arguments @('build', 'apk', '--release', $define)
            Write-DmOk 'APK: frontend\build\app\outputs\flutter-apk\app-release.apk'
            Write-DmWarn 'Copy/install this APK on the phone manually. It still needs LAN access to the selected backend.'
        } else {
            Write-DmStep "Run on the selected phone only: $($connection.DeviceId)"
            Invoke-DmFlutter -Flutter $flutter -Arguments @('run', '--release', '-d', $connection.DeviceId, $define)
        }
    } finally { Pop-Location }
}

function Invoke-DmDiagnostics {
    param([string]$Root, [string]$AdbPath = '', [int]$Port = 8000)
    Write-DmStep 'Source API default'
    Write-Host "  $(Get-DmConfigUrl -Root $Root) (app runtime setting/build-time defines may override this)"
    Write-DmStep 'Backend health on this PC'
    $result = Test-DmBackend -ApiBase "http://127.0.0.1:$Port/api"
    Write-Host "  Health matches DriveMate: $($result.Ok); HTTP $($result.StatusCode)"
    Write-DmStep 'Physical LAN candidates (virtual/host-only/VPN excluded)'
    try { Get-DmLanCandidates -Configurations @(Get-DmNetworkConfigurations) | Format-Table -AutoSize | Out-Host }
    catch { Write-DmWarn $_.Exception.Message }
    Write-DmStep 'ADB list - read only'
    try {
        $adb = Find-DmAdb -AdbPath $AdbPath
        $devices = @(Get-DmDevices -Adb $adb)
        if (@($devices | Where-Object { $_.State -eq 'device' -and -not $_.IsEmulator }).Count -eq 0) { Show-DmUsbHelp }
    } catch { Write-DmWarn $_.Exception.Message }
    Write-DmWarn 'Diagnosis only: no source, firewall, drivers, .env, database or device authorization was changed.'
}
