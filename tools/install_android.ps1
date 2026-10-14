param([string]$Serial, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_env.ps1')
$buildEnvironment = Get-AndroidBuildEnvironment
Set-AndroidBuildEnvironment $buildEnvironment
if (-not (Test-Path -LiteralPath $buildEnvironment.Adb)) { throw 'ADB missing. First run Build Android AR.cmd.' }

$devices = @(& $buildEnvironment.Adb devices)
if ($LASTEXITCODE -ne 0) { throw 'ADB device check failed.' }
$devices | ForEach-Object { Write-Host $_ }
$ready = @($devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($Serial) {
    if ($Serial -notin $ready) { throw "Device $Serial is not authorized/connected." }
} elseif ($ready.Count -eq 1) {
    $Serial = $ready[0]
} elseif ($ready.Count -eq 0) {
    throw 'No authorized phone. Enable USB debugging, connect a data USB cable, unlock phone and accept Allow USB debugging.'
} else {
    throw 'Multiple devices connected. Run tools/install_android.ps1 -Serial YOUR_DEVICE_SERIAL.'
}

$adbArguments = @('-s', $Serial)
foreach ($property in @('ro.product.model', 'ro.build.version.release', 'ro.product.cpu.abilist')) {
    $value = & $buildEnvironment.Adb @adbArguments shell getprop $property
    Write-Host "$property : $value"
}
$abi = & $buildEnvironment.Adb @adbArguments shell getprop ro.product.cpu.abilist
if ("$abi" -notmatch 'arm64-v8a') { throw 'This APK requires an ARM64 Android OS.' }
if ($CheckOnly) { exit 0 }
if (-not (Test-Path -LiteralPath $buildEnvironment.Apk)) { throw 'Updated APK not found. Build Android AR.cmd must finish first; the old PocketTerrainAR.apk is not this game.' }

& $buildEnvironment.Adb @adbArguments install -r $buildEnvironment.Apk
if ($LASTEXITCODE -ne 0) { throw 'APK installation failed. The phone may show a confirmation; see MOBILE_AR_GUIDE.md.' }
# Resolve the actual launcher component rather than hard-coding Godot's Activity.
$component = @(& $buildEnvironment.Adb @adbArguments shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p org.pocketterrain.demo) | Where-Object { $_ -match '^org\.pocketterrain\.demo/' } | Select-Object -Last 1
if (-not $component) { throw 'Installed, but launcher component was not found. Open Neon Volley AR on the phone.' }
& $buildEnvironment.Adb @adbArguments shell am start -n $component.Trim()
if ($LASTEXITCODE -ne 0) { throw 'Installed, but automatic launch failed. Open Neon Volley AR on the phone.' }
Write-Host 'Allow camera access. Aim at a table/floor and tap Place without scan, or scan until green and tap Place court.' -ForegroundColor Green
