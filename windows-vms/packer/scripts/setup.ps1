# Packer Post-Installation Setup für Windows Server 2025
# Läuft nach autounattend.xml, bevor Sysprep das Template versiegelt

$ErrorActionPreference = "Stop"

# ─── VirtIO Guest Tools installieren ──────────────────────────────────────────
# VirtIO ISO ist als zweites CD-Laufwerk eingebunden (D: / E: / F:)
$virtio = $env:VIRTIO_DRIVE
if (-not $virtio) { $virtio = "E:" }

$installer = "$virtio\virtio-win-gt-x64.msi"
if (-not (Test-Path $installer)) {
    # Laufwerksbuchstaben durchsuchen falls der konfigurierte falsch ist
    foreach ($drive in @("D:", "E:", "F:", "G:")) {
        if (Test-Path "$drive\virtio-win-gt-x64.msi") {
            $installer = "$drive\virtio-win-gt-x64.msi"
            break
        }
    }
}

if (Test-Path $installer) {
    Write-Host "Installiere VirtIO Guest Tools von $installer ..."
    Start-Process msiexec.exe -ArgumentList "/i `"$installer`" /qn /norestart" -Wait
    Write-Host "VirtIO Guest Tools installiert."
} else {
    Write-Warning "VirtIO Guest Tools Installer nicht gefunden — übersprungen."
}

# ─── WinRM HTTPS (Port 5986) konfigurieren ────────────────────────────────────
Write-Host "Konfiguriere WinRM HTTPS ..."

# Self-signed Zertifikat erstellen
$cert = New-SelfSignedCertificate `
    -Subject "CN=$env:COMPUTERNAME" `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(5)

# HTTPS Listener erstellen
$existingListener = Get-ChildItem WSMan:\localhost\Listener | Where-Object {
    $_.Keys -contains "Transport=HTTPS"
}
if ($existingListener) {
    Remove-Item -Path "WSMan:\localhost\Listener\$($existingListener.Name)" -Recurse -Force
}

New-Item -Path WSMan:\localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force | Out-Null

# HTTPS Firewall-Regel
$fwRule = Get-NetFirewallRule -DisplayName "WinRM HTTPS" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule `
        -DisplayName "WinRM HTTPS" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5986 `
        -Action Allow `
        -Profile Any | Out-Null
}

# WinRM Dienst sicherstellen
Set-Item WSMan:\localhost\Service\Auth\Basic $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted $false
Restart-Service WinRM
Write-Host "WinRM HTTPS auf Port 5986 aktiviert."

# ─── Windows Defender Realtime Scan deaktivieren (optional, für Lab-Umgebung) ─
Set-MpPreference -DisableRealtimeMonitoring $true

# ─── Unnötige Dienste für Template deaktivieren ────────────────────────────────
$disableServices = @("wuauserv", "WaaSMedicSvc")
foreach ($svc in $disableServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
}

# ─── Temp-Dateien bereinigen ────────────────────────────────────────────────────
Write-Host "Bereinige temporäre Dateien ..."
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Setup abgeschlossen — Packer führt Sysprep aus."
