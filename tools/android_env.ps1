$ErrorActionPreference = 'Stop'

function Get-AndroidBuildEnvironment {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $toolRoot = Join-Path $projectRoot '.tools'
    $javaCandidates = @()
    if ($env:JAVA_HOME) { $javaCandidates += $env:JAVA_HOME }
    $javaCandidates += @(Get-ChildItem (Join-Path $toolRoot 'jdk') -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $javaCandidates += @(Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $javaRoot = $javaCandidates | Where-Object { Test-Path (Join-Path $_ 'bin/java.exe') } | Select-Object -First 1
    if (-not $javaRoot) { throw 'JDK missing. Run python tools/download_tools.py or set JAVA_HOME to JDK 17.' }
    $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $toolRoot 'android-sdk' }
    [pscustomobject]@{
        ProjectRoot = $projectRoot
        ToolRoot = $toolRoot
        JavaHome = $javaRoot
        SdkRoot = $sdkRoot
        SdkManager = Join-Path $toolRoot 'sdk/cmdline-tools/bin/sdkmanager.bat'
        Gradle = Join-Path $toolRoot 'gradle/gradle-8.9/bin/gradle.bat'
        Godot = Join-Path $toolRoot 'godot/Godot_v4.5.1-stable_win64_console.exe'
        Apk = Join-Path $projectRoot 'build/NeonVolleyAR.apk'
        Adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
    }
}

function Set-AndroidBuildEnvironment($buildEnvironment) {
    $env:JAVA_HOME = $buildEnvironment.JavaHome
    $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
    $env:ANDROID_HOME = $buildEnvironment.SdkRoot
    $env:ANDROID_SDK_ROOT = $buildEnvironment.SdkRoot
    $env:GRADLE_USER_HOME = Join-Path $buildEnvironment.ToolRoot 'gradle-cache'
    $env:APPDATA = Join-Path $buildEnvironment.ToolRoot 'user'
    $env:LOCALAPPDATA = $env:APPDATA
    $env:ANDROID_USER_HOME = Join-Path $buildEnvironment.ToolRoot 'android-user'
    New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME -Force | Out-Null
}
