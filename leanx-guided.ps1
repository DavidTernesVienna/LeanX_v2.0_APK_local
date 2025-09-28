# leanx-guided.ps1  (ASCII clean)
# Schritt-fuer-Schritt Assistent mit Bestaetigungen (J/N)

$ErrorActionPreference = "Stop"

# ---- Projektpfade / IDs ----
$ProjectRoot = "C:\Users\larst\Code\LeanX_v2.0_APK"
$AndroidDir  = Join-Path $ProjectRoot "android"
$DefaultZip  = "C:\Users\larst\Downloads\leanx.zip"
$PkgRelease  = "com.david.leanx"
$PkgDebug    = "com.david.leanx.debug"
$MainRel     = "$PkgRelease/$PkgRelease.MainActivity"
$MainDbg     = "$PkgDebug/$PkgDebug.MainActivity"

function Info($m){ Write-Host "[i] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK] $m" -ForegroundColor Green }
function Die($m){ Write-Host "[X] $m" -ForegroundColor Red; exit 1 }
function Ask($m){
  while ($true) {
    $r = Read-Host "$m (J/N)"
    if ($r -match '^[JjYy]$') { return $true }
    if ($r -match '^[Nn]$') { Die "Abgebrochen durch Benutzer." }
  }
}

# 0) adb vorhanden?
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Die "adb nicht gefunden. Bitte Android Platform-Tools installieren und ...\Android\Sdk\platform-tools zum PATH hinzufuegen."
}

# 1) ZIP-Datei waehlen
$zipPath = Read-Host "Pfad zur ZIP angeben oder Enter fuer Standard [$DefaultZip]"
if ([string]::IsNullOrWhiteSpace($zipPath)) { $zipPath = $DefaultZip }
if (-not (Test-Path $zipPath)) { Die "ZIP nicht gefunden: $zipPath" }

$zipInfo = Get-Item $zipPath
Info ("ZIP: {0} | Groesse: {1} MB | Datum: {2}" -f $zipInfo.FullName, [math]::Round($zipInfo.Length/1MB,2), $zipInfo.LastWriteTime)
Ask "ZIP entpacken?"

# 2) ZIP in Temp entpacken
$Tmp = Join-Path $env:TEMP ("leanx_web_" + (Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $Tmp -Force
Ok "ZIP entpackt nach: $Tmp"

# 3) Web-Root finden (Ordner, der package.json oder index.html enthaelt)
function Find-WebRoot([string]$base){
  $pkg = Join-Path $base "package.json"
  $idx = Join-Path $base "index.html"
  if ((Test-Path $pkg) -or (Test-Path $idx)) { return $base }

  # Rekursiv zuerst nach package.json, sonst nach index.html suchen
  $pkgHit = Get-ChildItem -Path $base -Recurse -File -Filter "package.json" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pkgHit) { return $pkgHit.Directory.FullName }

  $idxHit = Get-ChildItem -Path $base -Recurse -File -Filter "index.html" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($idxHit) { return $idxHit.Directory.FullName }

  return $null
}

$WebSrc = Find-WebRoot $Tmp
if (-not $WebSrc) { Die "Weder package.json noch index.html irgendwo im ZIP gefunden." }
Info "Arbeitsordner: $WebSrc"

# 4) Source (package.json) oder fertiger Build (index.html)?
$PkgJson   = Join-Path $WebSrc "package.json"
$IndexHtml = Join-Path $WebSrc "index.html"
$DistFrom  = $null

if (Test-Path $PkgJson) {
  Info "Source erkannt (package.json vorhanden)."
  Ask "npm Abhaengigkeiten installieren (npm ci/install) und Web-Build erzeugen (npx vite build)?"
  Push-Location $WebSrc
  try {
    if (Test-Path (Join-Path $WebSrc "package-lock.json")) { npm ci } else { npm install }
    npx vite build
  } finally { Pop-Location }
  $DistFrom = Join-Path $WebSrc "dist"
  if (-not (Test-Path $DistFrom)) { Die "dist wurde nicht erzeugt." }
  Ok "Web-Build erzeugt: $DistFrom"
}
else {
  # kein package.json -> fertiger Web-Export
  if (-not (Test-Path $IndexHtml)) { Die "index.html nicht gefunden (unerwartet)." }
  Info "Bereits gebauter Web-Export erkannt (index.html vorhanden)."
  $DistFrom = $WebSrc
}

# 5) dist ins Projekt kopieren (altes dist sichern)
$DistTo = Join-Path $ProjectRoot "dist"
if (Test-Path $DistTo) {
  $Backup = Join-Path $ProjectRoot ("dist_backup_" + (Get-Date -Format yyyyMMdd_HHmmss))
  Info "Altes dist wird gesichert nach: $Backup"
  Ask "dist sichern und neues dist uebernehmen?"
  New-Item -ItemType Directory -Force -Path $Backup | Out-Null
  Copy-Item -Path (Join-Path $DistTo "*") -Destination $Backup -Recurse -Force
  Remove-Item $DistTo -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $DistTo | Out-Null
Copy-Item -Path (Join-Path $DistFrom "*") -Destination $DistTo -Recurse -Force
Ok "dist aktualisiert: $DistTo"

# 6) Capacitor: dist -> android assets
Ask "Capacitor Sync (npx cap sync android) ausfuehren?"
Push-Location $ProjectRoot
try {
  npx cap sync android
} finally {
  Pop-Location
}
Ok "Capacitor Sync abgeschlossen."

# 7) Build-Typ waehlen
$buildChoice = Read-Host "Release bauen (empfohlen) = R, Debug = D?"
$BuildType = if ($buildChoice -match '^[Rr]$') { "release" } else { "debug" }
Info "Build-Typ: $BuildType"
Ask "Gradle-Build starten?"

# 8) Gradle-Build
Push-Location $AndroidDir
try {
  .\gradlew.bat --stop | Out-Null
  if ($BuildType -eq "release") {
    .\gradlew.bat clean assembleRelease --stacktrace
  } else {
    .\gradlew.bat clean assembleDebug --stacktrace
  }
} catch {
  Die "Gradle-Build fehlgeschlagen."
} finally {
  Pop-Location
}
Ok "Build fertig."

# 9) APK-Pfad ermitteln
$Apk = if ($BuildType -eq "release") {
  Join-Path $AndroidDir "app\build\outputs\apk\release\app-release.apk"
} else {
  Join-Path $AndroidDir "app\build\outputs\apk\debug\app-debug.apk"
}
if (-not (Test-Path $Apk)) { Die "APK nicht gefunden: $Apk" }
Info "APK: $Apk"

# 10) Geraet pruefen
$adbOut = & adb devices
$devLines = $adbOut -split "`r?`n" | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)$' }
if ($devLines.Count -eq 0) { Die "Kein Geraet gefunden. USB-Debugging an? (adb devices pruefen)" }
if ($devLines -match 'unauthorized$') { Die "Geraet 'unauthorized'. Bitte Debugging-Abfrage am Handy bestaetigen." }
if ($devLines -match 'offline$') { Die "Geraet 'offline'. Kabel neu anstecken oder 'adb kill-server'." }

# 11) Alte App deinstallieren
$pkg = if ($BuildType -eq "release") { $PkgRelease } else { $PkgDebug }
Info "Ziel-Package: $pkg"
Ask "Alte App deinstallieren (falls vorhanden)?"
adb uninstall $pkg | Out-Null

# 12) APK installieren
Ask "Neue APK installieren?"
adb install -r "$Apk"
if ($LASTEXITCODE -ne 0) { Die "Installation fehlgeschlagen." }
Ok "Installation erfolgreich."

# 13) App starten
$mainAct = if ($BuildType -eq "release") { $MainRel } else { $MainDbg }
Ask "App jetzt starten?"
adb shell am start -n $mainAct
if ($LASTEXITCODE -ne 0) { Die "Start fehlgeschlagen. Activity pruefen oder 'adb logcat'." }
Ok "App gestartet."

# 14) Temp aufraeumen
Ask "Temporaren Ordner loeschen?"
Remove-Item $Tmp -Recurse -Force
Ok "Fertig."
