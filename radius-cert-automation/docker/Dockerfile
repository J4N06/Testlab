FROM python:3.11-slim

WORKDIR /app

# Systempakete für NTLM-Authentifizierung
RUN apt-get update && apt-get install -y --no-cache \
    krb5-user \
    && rm -rf /var/lib/apt/lists/*

# Python-Abhängigkeiten
RUN pip install --no-cache-dir \
    pywinrm[kerberos] \
    cryptography \
    requests

COPY deploy-cert.py .

CMD ["python", "deploy-cert.py"]
