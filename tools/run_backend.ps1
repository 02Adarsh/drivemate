#requires -Version 5.1
<# V9.1 backend launcher. Uses the EXISTING venv; never deletes DB/.env/uploads. #>
[CmdletBinding()]
param([switch]$SkipInstall,[ValidateRange(1,65535)][int]$Port=8000)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$backend=Join-Path $root 'backend'
$python=Join-Path $backend '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    Write-Host '[X] backend\.venv\Scripts\python.exe not found. Restore/create the Python environment first. Your database was not changed.' -ForegroundColor Red
    exit 1
}
Push-Location $backend
$oldSettings=$env:DJANGO_SETTINGS_MODULE
try {
    $env:DJANGO_SETTINGS_MODULE='config.settings'
    if (-not $SkipInstall) {
        Write-Host '=== Install/update backend requirements (includes QR decoding/generation and PDF receipts)' -ForegroundColor Cyan
        & $python -m pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Server was not started.' }
    }
    Write-Host '=== Validate Django' -ForegroundColor Cyan
    & $python -m django check
    if ($LASTEXITCODE -ne 0) { throw 'Django check failed. Read the error above.' }
    Write-Host '=== Apply included migrations (keeps existing users/data)' -ForegroundColor Cyan
    & $python -m django migrate --noinput
    if ($LASTEXITCODE -ne 0) { throw 'Migrations failed. Server was not started. Do not delete the database.' }
    Write-Host "=== V9.1 API 10: http://127.0.0.1:$Port/api/health/ - leave this terminal running" -ForegroundColor Green
    Write-Host 'Email OTP needs the real SMTP values in backend/.env. No password/key is printed by this script.'
    & $python -m django runserver "0.0.0.0:$Port"
    exit $LASTEXITCODE
} catch {
    Write-Host "[X] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    $env:DJANGO_SETTINGS_MODULE=$oldSettings
    Pop-Location
}
