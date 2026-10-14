param([switch]$InstallSdk, [switch]$ExportApk, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_env.ps1')
$buildEnvironment = Get-AndroidBuildEnvironment
Set-AndroidBuildEnvironment $buildEnvironment

$required = @(
    $buildEnvironment.SdkManager,
    $buildEnvironment.Gradle,
    $buildEnvironment.Godot,
    (Join-Path $buildEnvironment.ToolRoot 'godot/editor_data/export_templates/4.5.1.stable/android_source.zip'),
    (Join-Path $buildEnvironment.ProjectRoot 'native/pocket-ar/src/main/assets/hand_landmarker.task')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required tool/resource missing: $path. See MOBILE_AR_GUIDE.md." }
}

Write-Host "Java: $env:JAVA_HOME"
Write-Host "Android SDK: $env:ANDROID_HOME"
$sdkComponents = @('platform-tools/adb.exe', 'platforms/android-35/android.jar', 'build-tools/35.0.0/apksigner.bat', 'ndk/28.1.13356709/source.properties', 'cmake/3.10.2.4988404/bin/cmake.exe')
$initialMissing = @($sdkComponents | Where-Object { -not (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME $_)) })
if ($InstallSdk -and $initialMissing.Count -gt 0) {
    Write-Host 'Google SDK license prompts follow. Read the terms and accept only if you agree.'
    Write-Host 'The first setup downloads SDK tools and the NDK; allow several GB of space.'
    & $buildEnvironment.SdkManager "--sdk_root=$env:ANDROID_HOME" 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0' 'ndk;28.1.13356709' 'cmake;3.10.2.4988404'
    if ($LASTEXITCODE -ne 0) { throw 'SDK setup failed or licenses were declined. Rerun Build Android AR.cmd after resolving it.' }
} elseif ($InstallSdk) {
    Write-Host 'SDK packages already installed; skipping SDK downloads.'
}

$missing = @()
foreach ($relative in $sdkComponents) {
    if (-not (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME $relative))) { $missing += $relative }
}
if ($missing.Count -gt 0) {
    Write-Host ('Missing SDK components: ' + ($missing -join ', ')) -ForegroundColor Yellow
    if ($CheckOnly) { exit 2 }
    throw 'Run Build Android AR.cmd to install SDK packages and review the license prompts.'
}
if ($CheckOnly) {
    Write-Host 'Android build prerequisites are ready.' -ForegroundColor Green
    exit 0
}

Push-Location (Join-Path $buildEnvironment.ProjectRoot 'native')
try {
    & $buildEnvironment.Gradle --no-daemon --max-workers=2 '-Dorg.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8' '-Pkotlin.compiler.execution.strategy=in-process' :pocket-ar:assembleRelease
    if ($LASTEXITCODE -ne 0) { throw 'Native ARCore plugin build failed.' }
} finally { Pop-Location }
Copy-Item -LiteralPath (Join-Path $buildEnvironment.ProjectRoot 'native/pocket-ar/build/outputs/aar/pocket-ar-release.aar') -Destination (Join-Path $buildEnvironment.ProjectRoot 'addons/pocket_ar/pocket-ar-release.aar')
Write-Host 'ARCore + MediaPipe plugin rebuilt.'

if ($ExportApk) {
    & python (Join-Path $PSScriptRoot 'configure_android.py')
    if ($LASTEXITCODE -ne 0) { throw 'Bundled Godot editor setup failed.' }
    New-Item -ItemType Directory -Path (Join-Path $buildEnvironment.ProjectRoot 'build') -Force | Out-Null
    # Export to a separate name; never confuse the old terrain APK with this build.
    $signer = Join-Path $env:ANDROID_HOME 'build-tools/35.0.0/apksigner.bat'
    $exportLog = Join-Path $buildEnvironment.ToolRoot 'export.log'
    $exportStarted = Get-Date
    $exportArguments = @('--headless', '--path', ('"{0}"' -f $buildEnvironment.ProjectRoot), '--log-file', ('"{0}"' -f $exportLog), '--export-debug', 'Android', ('"{0}"' -f $buildEnvironment.Apk))
    $exportProcess = Start-Process -FilePath $buildEnvironment.Godot -ArgumentList $exportArguments -WindowStyle Hidden -PassThru
    $verifiedAt = $null
    while (-not $exportProcess.HasExited) {
        Start-Sleep -Seconds 2
        $exportProcess.Refresh()
        $artifact = Get-Item -LiteralPath $buildEnvironment.Apk -ErrorAction SilentlyContinue
        $exportDone = (Test-Path -LiteralPath $exportLog) -and (Select-String -LiteralPath $exportLog -SimpleMatch '[ DONE ] export' -Quiet)
        if ($artifact -and $artifact.LastWriteTime -ge $exportStarted -and $exportDone) {
            if (-not $verifiedAt) {
                & $signer verify $buildEnvironment.Apk
                if ($LASTEXITCODE -eq 0) { $verifiedAt = Get-Date }
            } elseif (((Get-Date) - $verifiedAt).TotalSeconds -ge 15 -and -not $exportProcess.HasExited) {
                # Some Godot editor builds hang during shutdown after a successful export.
                Write-Host 'APK export and signature are complete; closing the stalled exporter.'
                Stop-Process -Id $exportProcess.Id
                break
            }
        }
        if (((Get-Date) - $exportStarted).TotalMinutes -gt 15) {
            Stop-Process -Id $exportProcess.Id
            throw 'Export timed out. See .tools/export.log.'
        }
    }
    $artifact = Get-Item -LiteralPath $buildEnvironment.Apk -ErrorAction SilentlyContinue
    if (-not $artifact -or $artifact.LastWriteTime -lt $exportStarted) { throw 'No fresh APK produced. See .tools/export.log.' }
    & $signer verify --verbose $buildEnvironment.Apk
    if ($LASTEXITCODE -ne 0) { throw 'Exported APK signature verification failed.' }
    Write-Host "Ready to install: $($buildEnvironment.Apk)" -ForegroundColor Green
}
