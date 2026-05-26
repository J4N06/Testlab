# setup-winrm.ps1
# Auf dem Windows NPS Server als Administrator ausführen
# Richtet WinRM über HTTPS ein und erstellt einen Service Account

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=== WinRM HTTPS Setup für RADIUS Zertifikat-Automation ===" -ForegroundColor Cyan

# ─── Parameter (anpassen) ────────────────────────────────────────────────────
$ServiceAccountName = "svc-certdeploy"
$ServiceAccountDesc = "Service Account für automatisches Zertifikat-Deployment"
$FirewallRuleName   = "WinRM HTTPS Inbound"
$WinRMPort          = 5986

# ─── 1. WinRM aktivieren ─────────────────────────────────────────────────────
Write-Host "`n[1/6] WinRM aktivieren ..." -ForegroundColor Yellow
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-WSManInstance -ResourceURI "winrm/config" -ValueSet @{
    MaxTimeoutms = "60000"
}
Write-Host "WinRM aktiviert" -ForegroundColor Green

# ─── 2. Selbstsigniertes Zertifikat für WinRM erstellen ──────────────────────
Write-Host "`n[2/6] WinRM HTTPS Zertifikat erstellen ..." -ForegroundColor Yellow
$hostname = [System.Net.Dns]::GetHostName()
$winrmCert = New-SelfSignedCertificate `
    -DnsName $hostname `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(5) `
    -FriendlyName "WinRM HTTPS"
Write-Host "Zertifikat erstellt: $($winrmCert.Thumbprint)" -ForegroundColor Green

# ─── 3. WinRM HTTPS Listener einrichten ──────────────────────────────────────
Write-Host "`n[3/6] WinRM HTTPS Listener konfigurieren ..." -ForegroundColor Yellow

# Bestehenden HTTPS Listener entfernen falls vorhanden
$existingListener = Get-WSManInstance -ResourceURI "winrm/config/Listener" `
    -SelectorSet @{Address="*"; Transport="HTTPS"} `
    -ErrorAction SilentlyContinue
if ($existingListener) {
    Remove-WSManInstance -ResourceURI "winrm/config/Listener" `
        -SelectorSet @{Address="*"; Transport="HTTPS"}
    Write-Host "Alter HTTPS-Listener entfernt"
}

# Neuen HTTPS Listener erstellen
New-WSManInstance -ResourceURI "winrm/config/Listener" `
    -SelectorSet @{Address="*"; Transport="HTTPS"} `
    -ValueSet @{Hostname=$hostname; CertificateThumbprint=$winrmCert.Thumbprint} | Out-Null
Write-Host "HTTPS-Listener auf Port $WinRMPort erstellt" -ForegroundColor Green

# ─── 4. Firewall-Regel für WinRM HTTPS ───────────────────────────────────────
Write-Host "`n[4/6] Firewall-Regel erstellen ..." -ForegroundColor Yellow
$fwRule = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
if ($fwRule) {
    Remove-NetFirewallRule -DisplayName $FirewallRuleName
}
New-NetFirewallRule `
    -DisplayName $FirewallRuleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $WinRMPort `
    -Action Allow `
    -Profile Domain,Private | Out-Null
Write-Host "Firewall-Regel erstellt: Port $WinRMPort TCP eingehend" -ForegroundColor Green

# ─── 5. Service Account erstellen ────────────────────────────────────────────
Write-Host "`n[5/6] Service Account '$ServiceAccountName' erstellen ..." -ForegroundColor Yellow

$existingUser = Get-LocalUser -Name $ServiceAccountName -ErrorAction SilentlyContinue
if ($existingUser) {
    Write-Host "Service Account existiert bereits — überspringe" -ForegroundColor DarkYellow
} else {
    # Zufälliges Passwort generieren
    $chars    = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$"
    $password = -join ((1..24) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $securePw = ConvertTo-SecureString $password -AsPlainText -Force

    New-LocalUser `
        -Name        $ServiceAccountName `
        -Password    $securePw `
        -Description $ServiceAccountDesc `
        -PasswordNeverExpires:$true `
        -UserMayNotChangePassword:$true | Out-Null

    # Zur Gruppe "Remote Management Users" hinzufügen
    Add-LocalGroupMember -Group "Remote Management Users" -Member $ServiceAccountName
    # Zur Gruppe "Administrators" hinzufügen (nötig für Zertifikat-Import + Dienst-Neustart)
    Add-LocalGroupMember -Group "Administrators" -Member $ServiceAccountName

    Write-Host "Service Account erstellt" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== PASSWORT SICHER SPEICHERN (einmalige Anzeige) ===" -ForegroundColor Red
    Write-Host "Benutzer  : $ServiceAccountName" -ForegroundColor White
    Write-Host "Passwort  : $password" -ForegroundColor White
    Write-Host "Kubernetes Secret erstellen:" -ForegroundColor White
    Write-Host "  kubectl create secret generic <KUNDE>-credentials \" -ForegroundColor Cyan
    Write-Host "    --from-literal=windows_password='$password' \" -ForegroundColor Cyan
    Write-Host "    --from-literal=pfx_password='<PFX-PASSWORT-WÄHLEN>' \" -ForegroundColor Cyan
    Write-Host "    -n radius-<KUNDE>" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Red
}

# ─── 6. WinRM Dienst neu starten ─────────────────────────────────────────────
Write-Host "`n[6/6] WinRM Dienst neu starten ..." -ForegroundColor Yellow
Restart-Service WinRM -Force
Start-Sleep -Seconds 3
Write-Host "WinRM Dienst läuft" -ForegroundColor Green

# ─── Zusammenfassung ─────────────────────────────────────────────────────────
Write-Host "`n=== Setup abgeschlossen ===" -ForegroundColor Cyan
Write-Host "WinRM HTTPS Port : $WinRMPort"
Write-Host "Hostname         : $hostname"
Write-Host "Zertifikat       : $($winrmCert.Thumbprint)"
Write-Host ""
Write-Host "Verbindung testen mit test-connection.ps1"
