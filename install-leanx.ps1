<#  install-leanx.ps1 (fixed)
    - Deinstalliert vorhandene App
    - Installiert neue APK
    - (optional) startet die MainActivity
    - Robuste Geräte-Erkennung (kein 'device' als Befehl-Fehler mehr)
#>

param(
  [string]$ProjectAndroidDir = "C:\Users\larst\Code\LeanX_v2.0_APK\android",
  [string]$Package           = "com.david.leanx",       # Release-Package
  [string]$DebugPackage      = "com.david.leanx.debug", # Debug-Package (für -UninstallDebug)
  [string]$ApkPath,                                     # Wenn leer: Release, sonst Debug
  [switch]$UninstallDebug,                              # auch Debug-Variante entfernen
  [switch]$StartApp                                      # nach Installation starten
)

function Fail($msg){ Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }
function Info($msg){ Write-Host "[i] $msg" -ForegroundColor Cyan }
function Ok($msg){ Write-Host "[✓] $msg" -ForegroundColor Green }

# 0) adb vorhanden?
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Fail "adb nicht gefunden. Installiere Android Platform-Tools und füge Android\Sdk\platform-tools zum PATH hinzu."
}

# 1) Gerät prüfen (robust parsen)
$adbOut = & adb devices
$deviceLines = $adbOut -split "`r?`n" | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)$' }
if ($deviceLines.Count -eq 0) { Fail "Kein Gerät gefunden. USB verbunden? USB-Debugging an? 'adb devices' prüfen." }
if ($deviceLines -match '\sunauthorized$') { Fail "Gerät ist 'unauthorized'. Auf dem Handy die Debugging-Abfrage bestätigen und erneut ausführen." }
if ($deviceLines -match '\soffline$') { Fail "Gerät ist 'offline'. Kabel kurz trennen/neu stecken, dann erneut versuchen." }
if ($deviceLines.Count -gt 1) {
  Info "Mehrere Geräte erkannt – es wird das erste verwendet."
  # Optional: hier -s <serial> einbauen, falls du willst
}

# 2) APK ermitteln (falls nicht übergeben)
if (-not $ApkPath) {
  $release = Join-Path $ProjectAndroidDir "app\build\outputs\apk\release\app-release.apk"
  $debug   = Join-Path $ProjectAndroidDir "app\build\outputs\apk\debug\app-debug.apk"
  if (Test-Path $release) { $ApkPath = $release }
  elseif (Test-Path $debug) { $ApkPath = $debug }
  else { Fail "Keine APK gefunden. Baue zuerst (assembleRelease oder assembleDebug) oder gib -ApkPath an." }
}
if (-not (Test-Path $ApkPath)) { Fail "APK nicht gefunden: $ApkPath" }

Info "APK: $ApkPath"
Info "Package: $Package"

# 3) Alte App(s) deinstallieren
Info "Deinstalliere vorhandene Release-App (falls vorhanden)..."
& adb uninstall $Package | Out-Null

if ($UninstallDebug) {
  Info "Deinstalliere vorhandene Debug-App (falls vorhanden)..."
  & adb uninstall $DebugPackage | Out-Null
}

# 4) Installieren
Info "Installiere neue APK..."
& adb install -r "$ApkPath"
if ($LASTEXITCODE -ne 0) { Fail "Installation fehlgeschlagen." }
Ok "Installation erfolgreich."

# 5) (optional) Starten
if ($StartApp) {
  $mainActivity = "$Package/$Package.MainActivity"
  Info "Starte App... ($mainActivity)"
  & adb shell am start -n $mainActivity
  if ($LASTEXITCODE -ne 0) { Fail "Start fehlgeschlagen. Prüfe Activity-Namen oder Logcat." }
  Ok "App gestartet."
}

Ok "Fertig."
