<#  LeanX – Keystore + Release Build Helper (Windows PowerShell)
    - Erstellt upload-keystore mit verdeckter Passwort-Eingabe
    - Setzt ENV-Vars LEANX_STORE_PW / LEANX_KEY_PW
    - (optional) baut assembleRelease und installiert APK via ADB
#>

param(
  [string]$ProjectRoot = "C:\Users\larst\Code\LeanX_v2.0_APK",
  [string]$JdkHome     = "C:\Program Files\Eclipse Adoptium\jdk-21.0.8.9-hotspot",
  [switch]$BuildRelease,
  [switch]$InstallApk,
  [switch]$ForceNewKeystore # überschreibt bestehenden .jks
)

# ----------------- Setup & Helpers -----------------
$AndroidDir  = Join-Path $ProjectRoot "android"
$AppModule   = Join-Path $AndroidDir "app"
$Keystore    = Join-Path $AndroidDir "leanx-upload.jks"
$KeyAlias    = "leanx-upload"
$ReleaseApk  = Join-Path $AppModule "build\outputs\apk\release\app-release.apk"

function ConvertTo-Plain([SecureString]$s) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Add-ToPath([string]$p) {
  if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
}

function Require-Cmd($cmd, $hint) {
  $p = (Get-Command $cmd -ErrorAction SilentlyContinue)
  if (-not $p) { throw "Tool '$cmd' nicht gefunden. $hint" }
}

# ----------------- 1) Java/Gradle/ADB vorbereiten -----------------
if (!(Test-Path $JdkHome)) { throw "JDK nicht gefunden unter: $JdkHome" }
$env:JAVA_HOME = $JdkHome
Add-ToPath (Join-Path $JdkHome "bin")

# Gradle soll garantiert dieses JDK nutzen (auch aus IDE)
$GradleProps = Join-Path $AndroidDir "gradle.properties"
if (Test-Path $GradleProps) {
  $text = Get-Content $GradleProps -Raw
  $desired = "org.gradle.java.home=$($JdkHome -replace '\\','\\')"
  if ($text -notmatch [regex]::Escape("org.gradle.java.home=")) {
    Add-Content $GradleProps "`n$desired"
  } elseif ($text -notmatch [regex]::Escape($desired)) {
    $text = $text -replace "org\.gradle\.java\.home=.*", $desired
    Set-Content $GradleProps $text -Encoding UTF8
  }
}

Require-Cmd "keytool" "Keytool kommt mit dem JDK. Prüfe JAVA_HOME\bin."
Require-Cmd "adb"     "Installiere Android SDK Platform-Tools und füge '...\Android\Sdk\platform-tools' zum PATH hinzu."
Require-Cmd (Join-Path $AndroidDir "gradlew.bat") "Gradle Wrapper fehlt? Im android-Ordner ausführen."

# ----------------- 2) Keystore anlegen (interaktiv, verdeckt) -----------------
$create = $true
if ((Test-Path $Keystore) -and -not $ForceNewKeystore) {
  Write-Host "Keystore existiert bereits: $Keystore (überspringe Erstellung)."
  $create = $false
}

if ($create) {
  Write-Host "=== Keystore erstellen: $Keystore ==="
  $storePw = Read-Host "Keystore-Passwort eingeben (wird nicht angezeigt)" -AsSecureString
  $keyPw   = Read-Host "Key-Passwort eingeben (leer = gleich wie Keystore)" -AsSecureString

  $storePlain = ConvertTo-Plain $storePw
  $keyPlain   = if ($keyPw.Length -gt 0) { ConvertTo-Plain $keyPw } else { $storePlain }

  Push-Location $AndroidDir
  & keytool -genkeypair -v `
    -keystore $Keystore `
    -alias $KeyAlias `
    -storepass $storePlain `
    -keypass $keyPlain `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -dname "CN=LeanX, OU=Dev, O=LeanX, L=City, S=State, C=DE"
  if ($LASTEXITCODE -ne 0) { throw "Keystore-Erstellung fehlgeschlagen." }
  Pop-Location

  # Passwörter als ENV-Variablen für diesen Prozess setzen
  $env:LEANX_STORE_PW = $storePlain
  $env:LEANX_KEY_PW   = $keyPlain
  Write-Host "Keystore erstellt. ENV-Variablen LEANX_STORE_PW / LEANX_KEY_PW gesetzt (nur in dieser Session)."
} else {
  # Falls bereits vorhanden, Nutzer nach Passwörtern fragen, damit Build sie nutzt
  if (-not $env:LEANX_STORE_PW) { $env:LEANX_STORE_PW = ConvertTo-Plain (Read-Host "Keystore-Passwort eingeben (für Build)" -AsSecureString) }
  if (-not $env:LEANX_KEY_PW)   { $env:LEANX_KEY_PW   = ConvertTo-Plain (Read-Host "Key-Passwort eingeben (für Build, Enter=gleich wie Keystore)" -AsSecureString); if (-not $env:LEANX_KEY_PW) { $env:LEANX_KEY_PW = $env:LEANX_STORE_PW } }
}

# ----------------- 3) Optional: Release bauen -----------------
if ($BuildRelease) {
  Push-Location $AndroidDir
  .\gradlew.bat --stop | Out-Null
  .\gradlew.bat clean assembleRelease
  if ($LASTEXITCODE -ne 0) { throw "Gradle Release-Build fehlgeschlagen." }
  Pop-Location
  if (!(Test-Path $ReleaseApk)) { throw "Release-APK nicht gefunden: $ReleaseApk" }
  Write-Host "Release-APK bereit: $ReleaseApk"
}

# ----------------- 4) Optional: Installieren -----------------
if ($InstallApk) {
  if (!(Test-Path $ReleaseApk)) { throw "Kein Release-APK gefunden. Starte das Skript mit -BuildRelease -InstallApk oder baue vorher." }
  & adb install -r $ReleaseApk
  if ($LASTEXITCODE -ne 0) { throw "ADB-Installation fehlgeschlagen." }
  Write-Host "APK installiert."
  # Optional direkt starten (Passe Package/Activity ggf. an)
  & adb shell am start -n com.david.leanx/com.david.leanx.MainActivity
}
