<#  install-leanx-oneclick.ps1
    1-Klick Installer für LeanX APK:
      - prüft adb & Gerät
      - nimmt bevorzugt Release-APK, sonst Debug
      - deinstalliert alte App (Release)
      - installiert APK
      - startet MainActivity
    Läuft mit Konsole oder als .exe (MessageBox-Ausgaben).
#>

# ======= Benutzeranpassung (falls nötig) =======
$ProjectAndroidDir = "C:\Users\larst\Code\LeanX_v2.0_APK\android"
$Package           = "com.david.leanx"          # Release-Package
$DebugPackage      = "com.david.leanx.debug"    # Debug-Package (wird nicht automatisch deinstalliert)
$MainActivity      = "$Package/$Package.MainActivity"
# ===============================================

# --- UI/Logging Helfer (Konsole + optional MessageBox) ---
$useGui = $false
try {
  # Wenn als .exe ohne Konsole: UserInteractive = $true, aber kein Host
  if ($Host.Name -notlike "*ConsoleHost*") { $useGui = $true }
} catch { $useGui = $true }

if ($useGui) {
  try { Add-Type -AssemblyName System.Windows.Forms | Out-Null } catch {}
}

function Say($msg) {
  if ($useGui) { [System.Windows.Forms.MessageBox]::Show($msg, "LeanX Installer", "OK", "Information") | Out-Null }
  Write-Host "[i] $msg" -ForegroundColor Cyan
}
function Ok($msg) {
  if ($useGui) { [System.Windows.Forms.MessageBox]::Show($msg, "LeanX Installer", "OK", "Information") | Out-Null }
  Write-Host "[✓] $msg" -ForegroundColor Green
}
function Die($msg, $code=1) {
  if ($useGui) { [System.Windows.Forms.MessageBox]::Show($msg, "LeanX Installer", "OK", "Error") | Out-Null }
  Write-Host "[X] $msg" -ForegroundColor Red
  exit $code
}

# --- 0) adb vorhanden? ---
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Die "adb nicht gefunden. Bitte Android Platform-Tools installieren und den Ordner '...\Android\Sdk\platform-tools' zum PATH hinzufügen."
}

# --- 1) Gerät prüfen ---
$adbOut = & adb devices
$deviceLines = $adbOut -split "`r?`n" | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)$' }

if ($deviceLines.Count -eq 0)     { Die "Kein Gerät gefunden. USB verbunden? USB-Debugging an? (Einstellungen → Entwickleroptionen → USB-Debugging)"; }
if ($deviceLines -match 'unauthorized$') { Die "Gerät ist 'unauthorized'. Bestätige die Debugging-Abfrage am Handy und versuche es erneut." }
if ($deviceLines -match 'offline$')      { Die "Gerät ist 'offline'. USB-Kabel kurz trennen/neu stecken oder 'adb kill-server' ausführen." }
if ($deviceLines.Count -gt 1) { Say "Mehrere Geräte erkannt – es wird das erste in der Liste verwendet." }

# --- 2) APK finden: zuerst Release, sonst Debug ---
$releaseApk = Join-Path $ProjectAndroidDir "app\build\outputs\apk\release\app-release.apk"
$debugApk   = Join-Path $ProjectAndroidDir "app\build\outputs\apk\debug\app-debug.apk"

$apk = $null
if (Test-Path $releaseApk) { $apk = $releaseApk }
elseif (Test-Path $debugApk) { $apk = $debugApk }

if (-not $apk) {
  Die "Keine APK gefunden. Bitte vorher bauen: 
- Release:  gradlew assembleRelease
- Debug:    gradlew assembleDebug"
}

Say "APK: $apk"
Say "Package: $Package"

# --- 3) Alte Release-App deinstallieren (falls vorhanden) ---
Say "Deinstalliere vorhandene Release-App (falls vorhanden)..."
& adb uninstall $Package | Out-Null

# --- 4) Installieren ---
Say "Installiere neue APK..."
& adb install -r "$apk"
if ($LASTEXITCODE -ne 0) { Die "Installation fehlgeschlagen (adb install). Prüfe Log/USB-Verbindung." }
Ok "Installation erfolgreich."

# --- 5) App starten ---
Say "Starte App... ($MainActivity)"
& adb shell am start -n $MainActivity
if ($LASTEXITCODE -ne 0) { Die "Start fehlgeschlagen. Prüfe Activity-Namen oder 'adb logcat'." }
Ok "App gestartet."

exit 0
