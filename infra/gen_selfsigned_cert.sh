#!/usr/bin/env bash
# Generate self-signed TLS cert for EC2 public IP (browser will warn once).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="$DIR/certs"
IP="${1:-}"

if [ -z "$IP" ]; then
  echo "Usage: $0 <public-ip>"
  exit 1
fi

mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "$CERT_DIR/privkey.pem" \
  -out "$CERT_DIR/fullchain.pem" \
  -subj "/CN=${IP}" \
  -addext "subjectAltName=IP:${IP}"

echo "Wrote $CERT_DIR/fullchain.pem and privkey.pem"
