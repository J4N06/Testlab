# test-connection.ps1
# Testet die WinRM-Verbindung und zeigt das aktuelle RADIUS-Zertifikat
# Ausführen: .\test-connection.ps1 -Host nps.kunde1.ch -User "KUNDE1\svc-certdeploy"

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetHost,

    [Parameter(Mandatory = $true)]
    [string]$User,

    [string]$Domain = "",

    [Parameter(Mandatory = $true)]
    [string]$CertDomain
)

$ErrorActionPreference = "Stop"

Write-Host "=== WinRM Verbindungstest ===" -ForegroundColor Cyan
Write-Host "Host       : $TargetHost"
Write-Host "Benutzer   : $User"
Write-Host "Zert-Domain: $CertDomain"
Write-Host ""

# ─── Credentials abfragen ────────────────────────────────────────────────────
$credential = Get-Credential -UserName $User -Message "Windows-Passwort für $TargetHost"

# ─── 1. WinRM Verbindung testen ──────────────────────────────────────────────
Write-Host "[1/4] Teste WinRM Verbindung ..." -ForegroundColor Yellow
try {
    $session = New-PSSession `
        -ComputerName $TargetHost `
        -Credential $credential `
        -UseSSL `
        -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)

    Write-Host "WinRM Verbindung erfolgreich" -ForegroundColor Green
} catch {
    Write-Host "FEHLER: WinRM Verbindung fehlgeschlagen!" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# ─── 2. NPS Dienst prüfen ────────────────────────────────────────────────────
Write-Host "`n[2/4] NPS Dienst (IAS) prüfen ..." -ForegroundColor Yellow
$svcStatus = Invoke-Command -Session $session -ScriptBlock {
    $svc = Get-Service -Name "IAS" -ErrorAction SilentlyContinue
    if ($svc) {
        [PSCustomObject]@{
            Name   = $svc.Name
            Status = $svc.Status
            Start  = $svc.StartType
        }
    } else {
        $null
    }
}

if ($svcStatus) {
    $color = if ($svcStatus.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "NPS Dienst: $($svcStatus.Status)" -ForegroundColor $color
} else {
    Write-Host "NPS Dienst (IAS) nicht gefunden!" -ForegroundColor Red
}

# ─── 3. Aktuelles RADIUS-Zertifikat anzeigen ─────────────────────────────────
Write-Host "`n[3/4] RADIUS-Zertifikate für '$CertDomain' ..." -ForegroundColor Yellow
$certs = Invoke-Command -Session $session -ArgumentList $CertDomain -ScriptBlock {
    param($domain)
    Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.Subject -like "*$domain*"
    } | ForEach-Object {
        [PSCustomObject]@{
            Thumbprint = $_.Thumbprint
            Subject    = $_.Subject
            NotBefore  = $_.NotBefore
            NotAfter   = $_.NotAfter
            DaysLeft   = [int](($_.NotAfter - (Get-Date)).TotalDays)
        }
    }
}

if ($certs) {
    foreach ($cert in $certs) {
        $color = if ($cert.DaysLeft -lt 30) { "Red" } elseif ($cert.DaysLeft -lt 60) { "Yellow" } else { "Green" }
        Write-Host ""
        Write-Host "  Thumbprint : $($cert.Thumbprint)"
        Write-Host "  Subject    : $($cert.Subject)"
        Write-Host "  Gültig ab  : $($cert.NotBefore.ToString('yyyy-MM-dd'))"
        Write-Host "  Ablauf     : $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor $color
        Write-Host "  Tage übrig : $($cert.DaysLeft)" -ForegroundColor $color
    }
} else {
    Write-Host "Kein Zertifikat für '$CertDomain' gefunden!" -ForegroundColor Red
}

# ─── 4. Erneuerung nötig? ────────────────────────────────────────────────────
Write-Host "`n[4/4] Prüfe ob Erneuerung nötig ..." -ForegroundColor Yellow
if ($certs) {
    $soonestExpiry = ($certs | Sort-Object DaysLeft | Select-Object -First 1)
    if ($soonestExpiry.DaysLeft -lt 30) {
        Write-Host "WARNUNG: Zertifikat läuft in $($soonestExpiry.DaysLeft) Tagen ab — Erneuerung nötig!" -ForegroundColor Red
    } elseif ($soonestExpiry.DaysLeft -lt 60) {
        Write-Host "HINWEIS: Zertifikat läuft in $($soonestExpiry.DaysLeft) Tagen ab" -ForegroundColor Yellow
    } else {
        Write-Host "OK: Zertifikat noch $($soonestExpiry.DaysLeft) Tage gültig" -ForegroundColor Green
    }
} else {
    Write-Host "Kein Zertifikat vorhanden — Deployment nötig!" -ForegroundColor Red
}

Remove-PSSession $session
Write-Host "`n=== Test abgeschlossen ===" -ForegroundColor Cyan
