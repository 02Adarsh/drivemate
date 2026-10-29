# No Pester / Windows hardware needed. Pure logic + mocked ADB/network/Flutter.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tools\tests\phone_helpers_test.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'phone_common.ps1')
$script:checks = 0
function Assert-DmTest { param([bool]$Value, [string]$Message) if (-not $Value) { throw "FAILED: $Message" }; $script:checks++ }
function Assert-DmThrows {
    param([scriptblock]$Action, [int]$Code)
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        Assert-DmTest ((Get-DmExitCode $_) -eq $Code) "Expected exit code $Code, got $(Get-DmExitCode $_): $($_.Exception.Message)"
    }
    Assert-DmTest $caught "Expected a failure with exit code $Code"
}

$tools = Split-Path -Parent $PSScriptRoot
foreach ($path in @((Join-Path $tools 'connect_phone.ps1'), (Join-Path $tools 'run_phone.ps1'), (Join-Path $tools 'phone_common.ps1'))) {
    $tokens = $null; $problems = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$problems) | Out-Null
    Assert-DmTest ($problems.Count -eq 0) "Syntax: $path"
}

$parsed = @(ConvertFrom-DmAdbDevices @('* daemon not running; starting now at tcp:5037', '* daemon started successfully',
    'List of devices attached', '', 'phone-A device product:p model:Pixel_8 device:x transport_id:1',
    'phone-B unauthorized usb:1-1', 'phone-C offline', 'emulator-5554 device product:sdk model:sdk_gphone64', 'phone-D no permissions'))
Assert-DmTest ($parsed.Count -eq 5) 'Ignore headers, blanks and normal daemon startup stderr'
Assert-DmTest ($parsed[0].Serial -eq 'phone-A' -and $parsed[0].State -eq 'device') 'Parse authorized device'
Assert-DmTest ($parsed[1].State -eq 'unauthorized') 'Parse unauthorized separately'
Assert-DmTest ($parsed[2].State -eq 'offline') 'Parse offline separately'
Assert-DmTest $parsed[3].IsEmulator 'Emulator is not a physical phone'
Assert-DmTest ($parsed[4].State -eq 'no_permissions') 'Recognize permissions state'
Assert-DmTest (@(ConvertFrom-DmAdbDevices @('List of devices attached','')).Count -eq 0) 'Empty adb list remains empty'
Assert-DmTest ((Select-DmDevice -Devices $parsed).Serial -eq 'phone-A') 'Choose the one ready physical phone'
Assert-DmThrows { Select-DmDevice -Devices @() } 15
Assert-DmThrows { Select-DmDevice -Devices @($parsed[3]) } 15
Assert-DmThrows { Select-DmDevice -Devices $parsed -DeviceId 'phone-B' } 13
Assert-DmThrows { Select-DmDevice -Devices $parsed -DeviceId 'not-listed' } 12
$two = @(ConvertFrom-DmAdbDevices @('phone-A device','phone-Z device'))
Assert-DmThrows { Select-DmDevice -Devices $two } 14
Assert-DmTest ((Select-DmDevice -Devices $two -DeviceId 'phone-Z').Serial -eq 'phone-Z') 'Multiple phones: explicit selection'

foreach ($ip in @('10.26.0.206','192.168.1.22','172.16.0.1','172.31.9.2')) { Assert-DmTest (Test-DmPrivateIPv4 $ip) "Private IP $ip" }
foreach ($ip in @('8.8.8.8','127.0.0.1','169.254.1.2','172.32.0.1','not-an-ip','::1')) { Assert-DmTest (-not (Test-DmPrivateIPv4 $ip)) "Reject $ip" }
function New-DmNetworkFixture {
    param([string]$Name,[string]$Ip,[bool]$Hardware=$true,[string]$Gateway='10.26.0.1',[string]$Status='Up')
    [pscustomobject]@{ InterfaceAlias=$Name; NetAdapter=[pscustomobject]@{ Status=$Status; HardwareInterface=$Hardware; InterfaceDescription=$Name };
        IPv4Address=@([pscustomobject]@{IPAddress=$Ip}); IPv4DefaultGateway=@([pscustomobject]@{NextHop=$Gateway}) }
}
$networks = @((New-DmNetworkFixture 'VirtualBox Host-Only' '192.168.56.1' $false ''),
    (New-DmNetworkFixture 'Wi-Fi' '10.26.0.206'), (New-DmNetworkFixture 'VPN' '10.2.3.4' $false),
    (New-DmNetworkFixture 'Ethernet down' '10.0.0.2' $true '10.0.0.1' 'Disconnected'),
    (New-DmNetworkFixture 'No gateway' '192.168.9.8' $true ''))
$candidates = @(Get-DmLanCandidates -Configurations $networks)
Assert-DmTest ($candidates.Count -eq 1 -and $candidates[0].Address -eq '10.26.0.206') 'User log: never select VirtualBox 192.168.56.1'
Assert-DmTest ((Select-DmLanAddress -Candidates $candidates) -eq '10.26.0.206') 'Single physical default-gateway interface'
Assert-DmThrows { Select-DmLanAddress -Candidates $candidates -LanIp '192.168.56.1' } 21
$multi = @($candidates[0], [pscustomobject]@{Address='192.168.1.10';Interface='Ethernet';Gateway='192.168.1.1'})
Assert-DmThrows { Select-DmLanAddress -Candidates $multi } 22
Assert-DmTest ((Select-DmLanAddress -Candidates $multi -LanIp '192.168.1.10') -eq '192.168.1.10') 'Explicit physical LAN choice'
Assert-DmThrows { Select-DmLanAddress -Candidates @() } 23

Assert-DmTest (ConvertFrom-DmHealth 200 '{"status":"ok","service":"drivemate-api"}').Ok 'Exact health identity'
Assert-DmTest (-not (ConvertFrom-DmHealth 200 '<html>other app</html>').Ok) 'HTTP 200 HTML is not healthy'
Assert-DmTest (-not (ConvertFrom-DmHealth 200 '{"status":"ok","service":"other"}').Ok) 'Different app is rejected'
Assert-DmTest (-not (ConvertFrom-DmHealth 400 '{"status":"ok","service":"drivemate-api"}').Ok) 'HTTP 400 is never healthy'
Assert-DmTest (-not (ConvertFrom-DmHealth 404 '{}').Ok) 'HTTP 404 is never healthy'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('drivemate-v8-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'frontend/lib') -Force | Out-Null
try {
    $config = Join-Path $temp 'frontend/lib/config.dart'
    $unicode = [string][char]0x20B9 + [char]0x0939 + [char]0x093F
    [IO.File]::WriteAllText($config, "// $unicode`nconst String apiDefaultBaseUrl = 'http://127.0.0.1:8000/api';`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    Set-DmConfigUrl -Root $temp -ApiBase 'http://10.26.0.206:8000/api'
    Assert-DmTest ((Get-DmConfigUrl -Root $temp) -eq 'http://10.26.0.206:8000/api') 'Write correct URL'
    Assert-DmTest ([IO.File]::ReadAllText($config,[Text.Encoding]::UTF8).Contains($unicode)) 'Preserve non-ASCII Dart text'
    $bytes = [IO.File]::ReadAllBytes($config)
    Assert-DmTest (-not ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'UTF-8 without BOM'
    Assert-DmThrows { Set-DmConfigUrl -Root $temp -ApiBase 'http://user:pass@host/api' } 31
    Assert-DmThrows { Set-DmConfigUrl -Root $temp -ApiBase 'ftp://host/api' } 31
    Assert-DmThrows { Set-DmConfigUrl -Root $temp -ApiBase 'http://host/api?key=secret' } 31

    $nativeExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $native = Invoke-DmNative -Command $nativeExe -Arguments @('-NoProfile','-Command', "[Console]::Error.WriteLine('* daemon started successfully'); [Console]::WriteLine('List of devices attached'); exit 0")
    Assert-DmTest ($native.ExitCode -eq 0) 'Normal stderr does not become a false native failure'
    Assert-DmTest (($native.Lines -join '|').Contains('daemon started successfully')) 'Native stderr captured for diagnostics'

    # Mock side effects AFTER testing the real parser/writer/native adapter.
    $script:deviceLines = @('List of devices attached')
    $script:adbCalls = @(); $script:flutterCalls = @(); $script:writes = @()
    $script:apiVersion=10; $script:healthOk = $true; $script:healthCode = 200; $script:reverseOk = $true; $script:failPub = $false
    function Find-DmAdb { param([string]$AdbPath) 'fixture-adb' }
    function Get-DmNetworkConfigurations { $networks }
    function Test-DmBackend { param([string]$ApiBase) [pscustomobject]@{Ok=$script:healthOk;StatusCode=$script:healthCode;ApiVersion=$script:apiVersion} }
    function Set-DmConfigUrl { param([string]$Root,[string]$ApiBase) $script:writes += $ApiBase }
    function Invoke-DmAdb {
        param([string]$Adb,[string[]]$Arguments)
        $script:adbCalls += ,$Arguments
        if ($Arguments[0] -eq 'devices') { return [pscustomobject]@{ExitCode=0;Lines=$script:deviceLines} }
        if (-not $script:reverseOk) { return [pscustomobject]@{ExitCode=1;Lines=@('reverse failed')} }
        if ($Arguments[-1] -eq '--list') { return [pscustomobject]@{ExitCode=0;Lines=@('UsbFfs tcp:8000 tcp:8000')} }
        [pscustomobject]@{ExitCode=0;Lines=@()}
    }
    function Find-DmFlutter { 'fixture-flutter' }
    function Invoke-DmFlutter {
        param([string]$Flutter,[string[]]$Arguments)
        $script:flutterCalls += ,$Arguments
        if ($script:failPub -and $Arguments[0] -eq 'pub') { Stop-DmConnection 'Fixture dependency failure' 61 }
    }

    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb } 15
    Assert-DmTest ($script:flutterCalls.Count -eq 0 -and $script:writes.Count -eq 0) 'Empty ADB list: no Flutter/source edit'
    Assert-DmTest ($script:adbCalls.Count -eq 1) 'Empty ADB list: no reverse command'
    $script:deviceLines = @('List of devices attached','phone-A unauthorized')
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb } 15
    Assert-DmTest ($script:flutterCalls.Count -eq 0) 'Unauthorized: no Flutter'
    $script:deviceLines = @('List of devices attached','phone-A device model:Pixel_8')
    $script:healthOk=$false; $script:healthCode=400
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb } 40
    Assert-DmTest ($script:flutterCalls.Count -eq 0 -and $script:writes.Count -eq 0) 'Bad ALLOWED_HOSTS: no build / source change'
    $script:healthOk=$true; $script:healthCode=200; $script:apiVersion=9
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb } 43
    $script:apiVersion=10
    $script:healthOk=$true; $script:healthCode=200; $script:reverseOk=$false
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb } 50
    Assert-DmTest ($script:flutterCalls.Count -eq 0) 'Failed reverse: no Flutter'
    $script:reverseOk=$true; $script:adbCalls=@()
    Invoke-DmPhoneLaunch -Root $temp -Mode Usb
    Assert-DmTest (($script:adbCalls[1] -join ' ') -eq '-s phone-A reverse tcp:8000 tcp:8000') 'Reverse targets selected serial'
    Assert-DmTest (($script:adbCalls[2] -join ' ') -eq '-s phone-A reverse --list') 'Reverse map is verified'
    Assert-DmTest (($script:flutterCalls[0] -join ' ') -eq 'pub get') 'Dependencies first'
    Assert-DmTest (($script:flutterCalls[1] -join ' ').Contains('run --release -d phone-A')) 'Flutter targets Android phone, never desktop'
    Assert-DmTest (($script:flutterCalls[1] -join ' ').Contains('API_BASE_URL=http://127.0.0.1:8000/api')) 'Explicit USB build address'

    $script:flutterCalls=@(); $script:adbCalls=@(); $script:deviceLines=@('List of devices attached')
    Invoke-DmPhoneLaunch -Root $temp -Mode Lan -BuildApk
    Assert-DmTest ($script:adbCalls.Count -eq 0) 'LAN APK build does not need an ADB device'
    Assert-DmTest (($script:flutterCalls[1] -join ' ').Contains('build apk --release')) 'APK-only build, not flutter run'
    Assert-DmTest (($script:flutterCalls[1] -join ' ').Contains('API_BASE_URL=http://10.26.0.206:8000/api')) 'APK embeds physical LAN, not VirtualBox IP'
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Usb -BuildApk } 62
    $script:failPub=$true; $script:flutterCalls=@()
    Assert-DmThrows { Invoke-DmPhoneLaunch -Root $temp -Mode Lan -BuildApk } 61
    Assert-DmTest ($script:flutterCalls.Count -eq 1) 'Dependency failure stops before APK/run'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "`nPASS: $script:checks assertions. ADB/network/Flutter mocked; real Windows hardware is not claimed." -ForegroundColor Green
