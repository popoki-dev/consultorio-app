# Gera as pastas de plataforma (android/ios) e aplica os ajustes nativos
# exigidos pelos plugins. Rode uma vez, de dentro da pasta do projeto:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Write-NoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText((Resolve-Path $path), $text)
}

# 1. Cria o que falta (não sobrescreve lib/, AndroidManifest.xml nem MainActivity.kt).
flutter create --org br.com.toru --project-name consultorio --platforms android,ios .
if ($LASTEXITCODE -ne 0) { throw 'flutter create falhou' }

# 2. Android: desugaring (flutter_local_notifications) e minSdk 23 (biometria/cofre).
$kts = 'android/app/build.gradle.kts'
$groovy = 'android/app/build.gradle'
if (Test-Path $kts) {
    $c = Get-Content $kts -Raw
    if ($c -notmatch 'isCoreLibraryDesugaringEnabled') {
        $c = $c -replace 'compileOptions \{', "compileOptions {`n        isCoreLibraryDesugaringEnabled = true"
    }
    $c = $c -replace 'minSdk = flutter\.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 23)'
    if ($c -notmatch 'desugar_jdk_libs') {
        $c += "`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
    }
    Write-NoBom $kts $c
} elseif (Test-Path $groovy) {
    $c = Get-Content $groovy -Raw
    if ($c -notmatch 'coreLibraryDesugaringEnabled') {
        $c = $c -replace 'compileOptions \{', "compileOptions {`n        coreLibraryDesugaringEnabled true"
    }
    $c = $c -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = Math.max(flutter.minSdkVersion, 23)'
    $c = $c -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion Math.max(flutter.minSdkVersion, 23)'
    if ($c -notmatch 'desugar_jdk_libs') {
        $c += "`ndependencies {`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`n}`n"
    }
    Write-NoBom $groovy $c
}

# 3. Plugins com Kotlin antigo compilam para JVM 1.8 enquanto o Java do
#    plugin usa 11/17. No Android a diferença é inofensiva (o D8 converte
#    tudo), então a checagem vira aviso em vez de quebrar o build.
$props = 'android/gradle.properties'
if ((Test-Path $props) -and -not (Select-String -Path $props -Pattern 'kotlin.jvm.target.validation.mode' -Quiet)) {
    Add-Content -Path $props -Value "`nkotlin.jvm.target.validation.mode=warning" -Encoding ascii
}

# 4. iOS: texto do Face ID e versão mínima.
$plist = 'ios/Runner/Info.plist'
if (Test-Path $plist) {
    $c = Get-Content $plist -Raw
    if ($c -notmatch 'NSFaceIDUsageDescription') {
        $re = [regex]'<dict>'
        $c = $re.Replace($c, "<dict>`n`t<key>NSFaceIDUsageDescription</key>`n`t<string>O Face ID protege os dados dos pacientes.</string>", 1)
        Write-NoBom $plist $c
    }
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou' }

Write-Host ''
Write-Host 'Pronto. Rode:  flutter run' -ForegroundColor Green
Write-Host 'Com sincronizacao:  flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...'
