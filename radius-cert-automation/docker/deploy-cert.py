#!/usr/bin/env python3
"""
Zertifikat-Deployment für Windows NPS (RADIUS) Server.
Wird als Kubernetes CronJob täglich ausgeführt.

Ablauf:
  1. TLS-Zertifikat aus /certs/ lesen (von cert-manager als Secret gemountet)
  2. Zertifikat in PFX konvertieren
  3. Via WinRM (NTLM) auf Windows NPS Server verbinden
  4. Altes RADIUS-Zertifikat entfernen, neues importieren
  5. NPS-Dienst (IAS) neu starten
  6. Benachrichtigung bei Erfolg/Fehler
"""

import base64
import logging
import os
import sys
import time
from datetime import datetime, timezone

import requests
import winrm
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

# ─── Konfiguration aus Umgebungsvariablen ────────────────────────────────────
WINDOWS_HOST  = os.environ["WINDOWS_HOST"]
WINDOWS_USER  = os.environ["WINDOWS_USER"]
WINDOWS_PASS  = os.environ["WINDOWS_PASS"]
CERT_DOMAIN   = os.environ["CERT_DOMAIN"]
PFX_PASSWORD  = os.environ.get("PFX_PASSWORD", "TempPfx2024!")
SLACK_WEBHOOK = os.environ.get("SLACK_WEBHOOK", "")

MAX_RETRIES  = 3
RETRY_DELAY  = 30   # Sekunden zwischen Versuchen
WINRM_PORT   = 5986  # HTTPS


# ─── Slack-Benachrichtigung ───────────────────────────────────────────────────
def notify(message: str, success: bool = True) -> None:
    """Optionale Slack-Benachrichtigung bei Erfolg oder Fehler."""
    log.info(f"{'✓' if success else '✗'} {message}")
    if not SLACK_WEBHOOK:
        return
    try:
        requests.post(
            SLACK_WEBHOOK,
            json={
                "attachments": [{
                    "color": "good" if success else "danger",
                    "title": f"RADIUS Zertifikat — {CERT_DOMAIN}",
                    "text": message,
                    "footer": f"Host: {WINDOWS_HOST} | {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                }]
            },
            timeout=10,
        )
    except Exception as exc:
        log.warning(f"Slack-Benachrichtigung fehlgeschlagen: {exc}")


# ─── Zertifikat lesen ─────────────────────────────────────────────────────────
def load_certificate() -> tuple[bytes, bytes, x509.Certificate]:
    """TLS-Zertifikat und Key aus /certs/ lesen (von Kubernetes Secret gemountet)."""
    log.info("Lese Zertifikat aus /certs/ ...")
    with open("/certs/tls.crt", "rb") as f:
        cert_pem = f.read()
    with open("/certs/tls.key", "rb") as f:
        key_pem = f.read()

    cert = x509.load_pem_x509_certificate(cert_pem)
    expires = cert.not_valid_after_utc
    days_left = (expires - datetime.now(timezone.utc)).days
    log.info(f"Zertifikat gültig bis: {expires.strftime('%Y-%m-%d')} (noch {days_left} Tage)")
    return cert_pem, key_pem, cert


# ─── PFX-Konvertierung ────────────────────────────────────────────────────────
def to_pfx(cert_pem: bytes, key_pem: bytes) -> bytes:
    """Zertifikat + Key → PFX (PKCS#12) mit Passwortschutz."""
    log.info("Konvertiere Zertifikat zu PFX ...")
    cert = x509.load_pem_x509_certificate(cert_pem)
    key  = serialization.load_pem_private_key(key_pem, password=None)

    pfx = pkcs12.serialize_key_and_certificates(
        name=CERT_DOMAIN.encode(),
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(PFX_PASSWORD.encode()),
    )
    log.info("PFX erfolgreich erstellt")
    return pfx


# ─── PowerShell-Skript ────────────────────────────────────────────────────────
def build_ps_script(pfx_b64: str) -> str:
    """PowerShell-Skript für Zertifikat-Import und NPS-Neustart."""
    return f"""
$ErrorActionPreference = "Stop"

# PFX aus Base64 in temporäre Datei schreiben
$pfxB64   = "{pfx_b64}"
$pfxBytes = [System.Convert]::FromBase64String($pfxB64)
$pfxPath  = "$env:TEMP\\radius-cert-$([System.Guid]::NewGuid()).pfx"
[System.IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

try {{
    # Altes RADIUS-Zertifikat entfernen
    Write-Host "Suche altes Zertifikat fuer {CERT_DOMAIN} ..."
    $oldCerts = Get-ChildItem Cert:\\LocalMachine\\My | Where-Object {{
        $_.Subject -like "*{CERT_DOMAIN}*"
    }}
    foreach ($c in $oldCerts) {{
        Write-Host "Entferne: $($c.Thumbprint) | Ablauf: $($c.NotAfter)"
        Remove-Item -Path "Cert:\\LocalMachine\\My\\$($c.Thumbprint)" -Force
    }}
    Write-Host "$($oldCerts.Count) altes Zertifikat(e) entfernt"

    # Neues Zertifikat importieren
    Write-Host "Importiere neues Zertifikat ..."
    $secPw  = ConvertTo-SecureString "{PFX_PASSWORD}" -AsPlainText -Force
    $newCert = Import-PfxCertificate `
        -FilePath $pfxPath `
        -CertStoreLocation Cert:\\LocalMachine\\My `
        -Password $secPw `
        -Exportable
    Write-Host "Importiert: Thumbprint=$($newCert.Thumbprint) | Ablauf=$($newCert.NotAfter)"

    # NPS-Dienst (IAS) neu starten
    Write-Host "Starte NPS-Dienst (IAS) neu ..."
    Restart-Service -Name "IAS" -Force
    Start-Sleep -Seconds 5

    $svc = Get-Service -Name "IAS"
    if ($svc.Status -ne "Running") {{
        throw "NPS-Dienst nicht gestartet! Status: $($svc.Status)"
    }}
    Write-Host "NPS-Dienst laeuft: $($svc.Status)"
    Write-Host "DEPLOYMENT ERFOLGREICH"
}}
finally {{
    # Temporäre PFX-Datei sicher löschen
    if (Test-Path $pfxPath) {{
        Remove-Item $pfxPath -Force
        Write-Host "Temporaere PFX-Datei geloescht"
    }}
}}
"""


# ─── WinRM Deployment ─────────────────────────────────────────────────────────
def deploy(pfx: bytes) -> None:
    """Zertifikat via WinRM auf Windows Server deployen."""
    pfx_b64 = base64.b64encode(pfx).decode()
    script  = build_ps_script(pfx_b64)

    log.info(f"Verbinde mit {WINDOWS_HOST}:{WINRM_PORT} via WinRM (NTLM) ...")
    session = winrm.Session(
        f"https://{WINDOWS_HOST}:{WINRM_PORT}/wsman",
        auth=(WINDOWS_USER, WINDOWS_PASS),
        transport="ntlm",
        server_cert_validation="ignore",  # Intern — kein öffentliches Zertifikat nötig
    )

    result = session.run_ps(script)

    stdout = result.std_out.decode("utf-8", errors="replace").strip()
    stderr = result.std_err.decode("utf-8", errors="replace").strip()

    if stdout:
        log.info(f"PowerShell stdout:\n{stdout}")
    if stderr:
        log.warning(f"PowerShell stderr:\n{stderr}")

    if result.status_code != 0:
        raise RuntimeError(f"PowerShell Fehlercode {result.status_code}: {stderr}")


# ─── Hauptprogramm ────────────────────────────────────────────────────────────
def main() -> None:
    log.info("=" * 60)
    log.info(f"RADIUS Zertifikat Deployment gestartet")
    log.info(f"Host: {WINDOWS_HOST} | Domain: {CERT_DOMAIN}")
    log.info("=" * 60)

    # Zertifikat lesen und konvertieren
    try:
        cert_pem, key_pem, cert = load_certificate()
        pfx = to_pfx(cert_pem, key_pem)
    except Exception as exc:
        msg = f"Fehler beim Zertifikat-Laden: {exc}"
        log.error(msg)
        notify(msg, success=False)
        sys.exit(1)

    # Deployment mit Retry-Logik
    last_error: Exception | None = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            log.info(f"--- Versuch {attempt}/{MAX_RETRIES} ---")
            deploy(pfx)
            notify(f"Zertifikat erfolgreich deployed (Versuch {attempt})", success=True)
            sys.exit(0)

        except ConnectionRefusedError as exc:
            last_error = exc
            log.warning(f"WinRM nicht erreichbar: {exc}")
        except Exception as exc:
            last_error = exc
            log.error(f"Fehler: {exc}")

        if attempt < MAX_RETRIES:
            log.info(f"Warte {RETRY_DELAY}s vor nächstem Versuch ...")
            time.sleep(RETRY_DELAY)

    msg = f"Deployment fehlgeschlagen nach {MAX_RETRIES} Versuchen. Letzter Fehler: {last_error}"
    log.error(msg)
    notify(msg, success=False)
    sys.exit(1)


if __name__ == "__main__":
    main()
